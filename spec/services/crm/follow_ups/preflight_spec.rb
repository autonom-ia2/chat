require 'rails_helper'

# Pré-voo (#1624): 10 min antes do envio fora da janela de 24 h, a IA compõe uma vez e o modelo do tipo é planejado (e criado,
# se a conta autorizou). Fronteiras em dublê: a IA (ResponsesClient) e o ponto único (`planejar`, que tem spec próprio).
RSpec.describe Crm::FollowUps::Preflight do
  include CrmHybridHelpers

  before do
    travel_to Time.utc(2026, 10, 16, 14)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    seed_crm_hybrid_transcript(scenario)
  end

  let(:plano) { { 'versao' => 1, 'tipo' => 'retorno', 'caminho' => 'criando', 'nome' => 'c2y_retorno_1', 'ja_recusado' => true } }
  let!(:scenario) do
    build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE], hybrid: false, last_inbound_ago: 30.hours.ago)
  end
  let!(:follow_up) do
    create_crm_hybrid_follow_up(scenario, source: 'ai_callback', metadata: { 'requested_at_text' => 'terça às 8h' })
      .tap { |created| created.update!(due_at: 5.minutes.from_now) }
  end

  def pre_voo
    described_class.new(follow_up: follow_up).call
    follow_up.reload.metadata['preflight']
  end

  def sem_modelo_que_sirva
    crm_hybrid_ai_answer({ 'should_send' => false, 'message_body' => '', 'confidence' => 0.2, 'decline_reason' => 'no_fitting_template' })
  end

  def planejando_retorno
    allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar).and_return(plano)
  end

  describe 'retorno combinado' do
    it 'nenhum modelo aprovado serve: uma chamada de IA, planeja o tipo já recusado e grava a composição' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva)
      planejando_retorno

      marca = pre_voo

      expect(ai_calls.size).to eq(1)
      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar)
        .with(hash_including(inbox: scenario[:inbox], tipo: 'retorno', ja_recusado: true, criar: true, contato: scenario[:contact]))
      expect(marca).to include('estado' => 'pronto', 'tipo' => 'retorno', 'plano' => plano, 'due_at' => described_class.horario(follow_up),
                               'at' => Time.current.iso8601)
      expect(marca['composicao']).to include('decline_reason' => 'no_fitting_template')
      expect(marca['candidatos']).to eq([['native', 'retomada_orcamento', nil, 'pt_BR']])
    end

    it 'a IA escolhe um modelo aprovado: grava a composição e NÃO cria modelo nenhum' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick,
                                              'template_variables' => [{ 'position' => '1', 'value' => 'Ana' }]))
      planejando_retorno

      marca = pre_voo

      expect(marca).to include('estado' => 'pronto')
      expect(marca).not_to have_key('plano')
      expect(marca['composicao']['chosen_template']).to include('index' => 0)
      expect(Whatsapp::Templates::EnvioForaDaJanela).not_to have_received(:planejar)
    end

    it 'a IA diz que não há o que enviar: nada de modelo novo' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva.merge('decline_reason' => 'nothing_to_send'))
      planejando_retorno

      expect(pre_voo).not_to have_key('plano')
      expect(Whatsapp::Templates::EnvioForaDaJanela).not_to have_received(:planejar)
    end

    it 'encerramento (o cliente já resolveu): nada de modelo novo' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva.merge('closure_detected' => true))
      planejando_retorno

      expect(pre_voo).not_to have_key('plano')
      expect(Whatsapp::Templates::EnvioForaDaJanela).not_to have_received(:planejar)
    end

    it 'idempotente: a segunda rodada não chama a IA nem o ponto único de novo' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva)
      planejando_retorno
      pre_voo

      described_class.new(follow_up: follow_up.reload).call

      expect(ai_calls.size).to eq(1)
      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar).once
      expect(described_class.pendente?(follow_up)).to be(false)
    end
  end

  describe 'quando NÃO roda' do
    before { stub_crm_hybrid_ai(sem_modelo_que_sirva) }

    it 'a janela de 24 h ainda está aberta no horário do envio' do
      scenario[:conversation].messages.incoming.last.update!(created_at: 2.hours.ago)

      expect(pre_voo).to be_nil
      expect(ai_calls).to be_empty
    end

    it 'avalia a janela NO HORÁRIO do envio: aberta agora, mas fechada quando o follow-up vencer' do
      scenario[:conversation].messages.incoming.last.update!(created_at: 23.hours.ago - 55.minutes)

      expect(pre_voo).to include('estado' => 'pronto')
    end

    it 'o número não é o oficial' do
      scenario[:inbox].update_columns(channel_type: 'Channel::Api') # rubocop:disable Rails/SkipsModelValidations

      expect(pre_voo).to be_nil
      expect(ai_calls).to be_empty
    end

    it 'a IA está desligada na instalação' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

      expect(pre_voo).to be_nil
    end

    it 'o funil desligou o retorno' do
      scenario[:card].pipeline.update!(metadata: { ai: { callback_enabled: false } })

      expect(pre_voo).to be_nil
      expect(ai_calls).to be_empty
    end

    it 'o contato está excluído do follow-up de IA' do
      scenario[:contact].update!(additional_attributes: { Crm::Ai::Config::CONTACT_FOLLOWUP_DISABLED_KEY => true })

      expect(pre_voo).to be_nil
      expect(ai_calls).to be_empty
    end

    it 'o follow-up não é automático de modelo (follow-up de IA comum)' do
      follow_up.update!(metadata: follow_up.metadata.merge('source' => 'ai_followup'))

      expect(described_class.pendente?(follow_up)).to be(false)
    end
  end

  describe 'o mundo muda durante a chamada lenta' do
    it 'o horário mudou: a marca antiga não vale e o pré-voo volta a ser pendente' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva) { follow_up.update!(due_at: 8.minutes.from_now) }
      planejando_retorno

      described_class.new(follow_up: follow_up).call

      expect(described_class.marca_vigente(follow_up.reload)).to be_nil
      expect(described_class.pendente?(follow_up)).to be(true)
    end

    it 'o follow-up foi cancelado: nada é gravado por cima' do
      stub_crm_hybrid_ai(sem_modelo_que_sirva) { follow_up.update!(status: :canceled, canceled_at: Time.current) }
      planejando_retorno

      described_class.new(follow_up: follow_up).call

      expect(follow_up.reload.metadata['preflight']['estado']).to eq('iniciado')
    end
  end

  describe 'falha da IA' do
    it 'grava a marca de erro e não repete a chamada paga a cada minuto' do
      client = stub_crm_hybrid_ai
      allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

      marca = pre_voo

      expect(marca).to include('estado' => 'erro', 'erro' => 'Crm::Ai::ResponsesClient::Error')
      expect(described_class.pendente?(follow_up)).to be(false)
      expect(described_class.marca_vigente(follow_up)).to be_nil
    end
  end

  describe 'cobrança (lembrete de Atender)' do
    let(:plano_de_cobranca) { { 'versao' => 1, 'tipo' => 'cobranca_no_dia', 'caminho' => 'modelo', 'nome' => 'cobranca_dia_vencimento' } }
    let!(:follow_up) do
      scenario[:card].update!(value_cents: 35_000, expected_close_at: Date.new(2026, 10, 16))
      create_crm_hybrid_follow_up(scenario, source: 'service_reminder', metadata: { 'kind' => 'payment_due', 'key' => 'payment_due:2026-10-16' })
        .tap { |created| created.update!(due_at: 5.minutes.from_now) }
    end

    before do
      allow(Crm::FollowUps::ServiceReminderScheduler).to receive(:wanted?).and_return(true)
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar).and_return(plano_de_cobranca)
    end

    it 'planeja o tipo do momento, com valor, criando o modelo; sem IA' do
      stub_crm_hybrid_ai

      marca = pre_voo

      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar)
        .with(hash_including(tipo: 'cobranca_no_dia', com_valor: true, ja_recusado: false, criar: true))
      expect(marca).to include('estado' => 'pronto', 'tipo' => 'cobranca_no_dia', 'plano' => plano_de_cobranca)
      expect(ai_calls).to be_empty
    end

    it 'o lembrete deixou de valer (vencimento mudou): não cria modelo' do
      allow(Crm::FollowUps::ServiceReminderScheduler).to receive(:wanted?).and_return(false)

      expect(pre_voo).to be_nil
      expect(Whatsapp::Templates::EnvioForaDaJanela).not_to have_received(:planejar)
    end

    it 'andamento e "deu certo?" não têm modelo: nada a fazer' do
      follow_up.update!(metadata: follow_up.metadata.merge('kind' => 'progress'))

      expect(described_class.pendente?(follow_up)).to be(false)
    end
  end
end
