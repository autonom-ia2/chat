require 'rails_helper'

# #2154: a fala do agente que avisou que vai chamar alguém já saiu; a IA de Atribuição avalia o card em foco, só a
# passagem. Sem token de agendamento, no máximo uma por conversa no intervalo, e com as guardas do Evaluator antes de
# agendar. Quando não avalia, o motivo vira evento do agente: o cliente ouviu "vou chamar alguém" e ninguém vem.
RSpec.describe Crm::Ai::AvaliacaoDepoisDaFala do
  include_context 'with crm responsible agent'

  let(:card) { create_card(pipeline: comercial) }
  let(:chave_do_intervalo) { format(described_class::CHAVE_DO_INTERVALO, conversa: conversation.id) }
  let(:chave_da_adiada) { format(described_class::CHAVE_DA_ADIADA, conversa: conversation.id) }
  let(:turno) { Autonomia::Agents::Operate::TurnoEmCurso }

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow_any_instance_of(Crm::Ai::CredentialResolver).to receive(:configured?).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow(Rails.logger).to receive(:info).and_call_original
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    [chave_do_intervalo, chave_da_adiada, turno.chave(conversation.id)].each { |chave| Redis::Alfred.delete(chave) }
  end

  def com_passagem!(enabled: true)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => enabled, 'handoff_mode' => 'r2_direct' } })
  end

  def agendar = described_class.agendar(conversation.reload)

  def nao_avaliou(motivo)
    Autonomia::Agents::AgentEvent.atribuicao_nao_avaliou.where(conversation_id: conversation.id)
                                 .where("metadata->>'motivo' = ?", motivo)
  end

  describe '.agendar' do
    it 'agenda a avaliação do card em foco com o gatilho da fala do agente, sem token', :aggregate_failures do
      com_passagem!

      expect { agendar }.to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(card.id, nil, described_class::TRIGGER)
      expect(Rails.logger).to have_received(:info).with(a_string_including("conversa=#{conversation.id}", 'desfecho=agendada'))
      expect(Autonomia::Agents::AgentEvent.atribuicao_nao_avaliou.count).to eq(0)
    end

    it 'não mexe no token da avaliação do cliente que já esperava a vez' do
      com_passagem!
      card.update!(metadata: { 'ai' => { 'evaluate_token' => 123.0 } })

      agendar

      expect(card.reload.metadata.dig('ai', 'evaluate_token')).to eq(123.0)
    end

    it 'o aviso repetido dentro do intervalo não é descartado: uma avaliação fica para quando o intervalo vence', :aggregate_failures do
      com_passagem!
      agendar
      resto = Redis::Alfred.ttl(chave_do_intervalo)

      freeze_time do
        expect { agendar }.to have_enqueued_job(Crm::Ai::EvaluateCardJob)
          .with(card.id, nil, described_class::TRIGGER)
          .at(be_within(2.seconds).of((resto + Crm::Ai::Config::DEBOUNCE_SECONDS).seconds.from_now))
      end
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=adiada_pelo_intervalo'))
    end

    it 'no máximo uma adiada: o terceiro aviso no intervalo é lido por ela, sem pagar outra', :aggregate_failures do
      com_passagem!
      2.times { agendar }

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=ja_adiada'))
      expect(Redis::Alfred.ttl(chave_do_intervalo)).to be_between(1, described_class::INTERVALO.to_i)
    end

    it 'funil sem passagem: não agenda, deixa a linha e o evento do agente', :aggregate_failures do
      com_passagem!(enabled: false)

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=sem_passagem'))
      expect(nao_avaliou('sem_passagem').sole.autonomia_agent_id).to eq(agente_da_porta.id)
    end

    it 'conversa sem card: não agenda, deixa a linha e o evento do agente', :aggregate_failures do
      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=sem_card'))
      expect(nao_avaliou('sem_card').count).to eq(1)
    end

    it 'funil com a IA desligada (a guarda do Evaluator): não agenda e diz o motivo real', :aggregate_failures do
      com_passagem!
      comercial.update!(metadata: { 'ai' => { 'enabled' => false } })

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(nao_avaliou('pipeline_ai_disabled').count).to eq(1)
    end

    it 'sem credencial da IA (a guarda do Evaluator): não agenda e diz o motivo real' do
      com_passagem!
      allow_any_instance_of(Crm::Ai::CredentialResolver).to receive(:configured?).and_return(false) # rubocop:disable RSpec/AnyInstance

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(nao_avaliou('credentials_missing').count).to eq(1)
    end

    it 'com a IA do CRM desligada, nada' do
      com_passagem!
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
    end

    it 'sem a flag, nada (a flag foi desligada no meio da entrega em pedaços)' do
      com_passagem!
      account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)

      expect { agendar }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
    end
  end

  # A avaliação SÓ DE PASSAGEM no Evaluator.
  describe 'a avaliação' do
    let(:classificacao) do
      { suggested_stage_id: comercial.stages.last.id, confidence: 0.99, reasoning: 'r', value: nil,
        handoff: { intent: 'continuar', should_handoff: false, reason: '', suggested_agent: nil },
        callback_request: nil, extracted_attributes: {}, score_signals: [] }
    end
    let(:classificador) { instance_double(Crm::Ai::StageClassifier, perform: classificacao) }

    before do
      com_passagem!
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
      allow_any_instance_of(Crm::Ai::CredentialResolver).to receive(:resolve).and_return(double) # rubocop:disable RSpec/AnyInstance
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(instance_double(Crm::Ai::ResponsesClient))
    end

    def avaliar = Crm::Ai::Evaluator.new(card: card.reload, trigger: described_class::TRIGGER).perform

    it 'não é cortada pelo intervalo entre avaliações e não derruba a do cliente: nem etapa, nem carimbo', :aggregate_failures do
      card.update!(metadata: { 'ai' => { 'last_evaluated_at' => 2.seconds.ago.iso8601, 'last_trigger' => 'message' } })
      antes = card.reload.metadata['ai'].dup

      expect(avaliar.status).to eq(:so_passagem)
      expect(card.reload.metadata['ai']).to eq(antes)
      expect(card.stage_id).to eq(comercial.stages.first.id)
      expect(Crm::Ai::Evaluator.new(card: card, trigger: 'message').motivo_para_pular).to eq('debounced')
    end

    it 'com o turno seguinte em curso, nem chama o modelo e volta depois, com a tentativa seguinte', :aggregate_failures do
      turno.abrir(conversation.id, 99)

      expect { expect(avaliar.error).to eq('fala_em_curso') }
        .to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(card.id, nil, described_class::TRIGGER, 1)
      expect(classificador).not_to have_received(:perform)
    end
  end

  # O turno seguinte em curso: a avaliação volta depois, respeitando o intervalo, e desiste no teto.
  describe '.reagendar' do
    before { com_passagem! }

    it 'volta com a espera crescendo pela tentativa e segura o intervalo até lá', :aggregate_failures do
      freeze_time do
        expect { described_class.reagendar(card, conversation, 2) }
          .to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(card.id, nil, described_class::TRIGGER, 3)
          .at(be_within(1.second).of((described_class::ESPERA_DA_FALA_EM_CURSO * 3).from_now))
      end
      expect(Redis::Alfred.ttl(chave_do_intervalo)).to be >= (described_class::ESPERA_DA_FALA_EM_CURSO * 3).to_i
    end

    it 'no teto de tentativas, desiste e deixa o evento fala_em_curso', :aggregate_failures do
      expect { described_class.reagendar(card, conversation, described_class::MAX_TENTATIVAS) }
        .not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
      expect(nao_avaliou('fala_em_curso').sole.autonomia_agent_id).to eq(agente_da_porta.id)
    end

    it 'um aviso novo enquanto ela espera é adiado, não vira outra avaliação imediata' do
      described_class.reagendar(card, conversation, 0)

      expect(agendar).to eq('adiada_pelo_intervalo')
    end
  end
end
