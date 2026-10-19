require 'rails_helper'

# Retorno combinado no horário, depois do pré-voo (#1624): a composição gravada é reusada sem 2ª chamada paga quando ainda
# descreve a situação, e o modelo do tipo (retorno) entra antes do texto livre do Híbrido quando nenhum aprovado serve.
# Só as fronteiras são dublês: a IA (ResponsesClient) e a conferência na Meta (DispatchCheck). O ponto único roda de verdade.
RSpec.describe Crm::FollowUps::CallbackRunner do
  include CrmHybridHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  before { travel_to Time.utc(2026, 10, 16, 14) }

  let(:hybrid) { false }
  let(:tipo_texto) { 'Olá, {{1}}! Aqui é da {{2}}. Voltamos ao seu pedido {{3}}, como combinado. Responda por aqui.' }
  let(:tipo_campos) { { '1' => 'cliente.primeiro_nome', '2' => 'minha_empresa.nome', '3' => 'negocio.titulo' } }
  let(:modelos) { [CrmHybridHelpers::APPROVED_TEMPLATE] }
  let!(:scenario) { build_crm_hybrid_scenario(templates: modelos, hybrid: hybrid, last_inbound_ago: 30.hours.ago) }
  let!(:follow_up) do
    create_crm_hybrid_follow_up(scenario, source: 'ai_callback', metadata: { 'requested_at_text' => 'terça às 8h', 'callback_retries' => 0 })
      .tap { |created| created.update!(due_at: Time.current) }
  end

  def rodar
    seed_crm_hybrid_transcript(scenario)
    described_class.new(follow_up: follow_up, now: Time.current).perform
  end

  def recusa_sem_modelo
    crm_hybrid_ai_answer({ 'should_send' => false, 'message_body' => '', 'confidence' => 0.2, 'decline_reason' => 'no_fitting_template' })
  end

  def candidatos
    [['native', 'retomada_orcamento', nil, 'pt_BR']]
  end

  def gravar_marca(composicao:, at: 5.minutes.ago, candidatos: self.candidatos, plano: nil)
    marca = { 'estado' => 'pronto', 'tipo' => 'retorno', 'at' => at.iso8601, 'due_at' => Crm::FollowUps::Preflight.horario(follow_up),
              'composicao' => composicao, 'candidatos' => candidatos }
    marca['plano'] = plano if plano
    follow_up.update!(metadata: follow_up.metadata.merge('preflight' => marca))
  end

  # Resposta crua da IA (variáveis em lista); o compositor a normaliza para o hash que o pré-voo grava.
  def escolhe_o_modelo(variaveis = [{ 'position' => '1', 'value' => 'Ana' }])
    crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick, 'template_variables' => variaveis)
  end

  # A composição como o `compose` a devolve (e o pré-voo a grava).
  def escolha_gravada
    escolhe_o_modelo({ '1' => 'Ana' })
  end

  describe 'composição gravada pelo pré-voo' do
    it 'reusa a composição: o envio não faz 2ª chamada paga à IA' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada)
      stub_crm_hybrid_ai

      result = nil
      expect { result = rodar }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_calls).to be_empty
      expect(follow_up.reload.metadata).to include('template_name' => 'retomada_orcamento', 'send_mode' => 'template')
    end

    it 'o cliente respondeu depois do pré-voo: a janela reabriu, o texto é livre e a IA compõe de novo (nada é reusado)' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada, at: 5.minutes.ago)
      create_incoming_message(conversation: scenario[:conversation]).update!(created_at: 2.minutes.ago)
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      result = rodar

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(['free_form'])
      expect(follow_up.reload.metadata).to include('send_mode' => 'session')
    end

    it 'o pré-voo é velho (passou da validade): compõe de novo' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada, at: 20.minutes.ago)
      stub_crm_hybrid_ai(escolhe_o_modelo)

      rodar

      expect(ai_calls.size).to eq(1)
    end

    it 'a lista de modelos aprovados mudou desde o pré-voo: o índice escolhido não vale, compõe de novo' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada, candidatos: [['native', 'outro_modelo', nil, 'pt_BR']])
      stub_crm_hybrid_ai(escolhe_o_modelo)

      rodar

      expect(ai_calls.size).to eq(1)
    end

    it 'o horário do follow-up mudou depois do pré-voo: a marca antiga não vale' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada)
      follow_up.update!(due_at: 1.minute.from_now)
      stub_crm_hybrid_ai(escolhe_o_modelo)

      described_class.new(follow_up: follow_up, now: 1.minute.from_now).perform

      expect(ai_calls.size).to eq(1)
    end

    it 'depois de uma tentativa que falhou: não reusa (nunca repete a mesma composição que já falhou)' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada)
      follow_up.update!(metadata: follow_up.metadata.merge('callback_retries' => 1))
      stub_crm_hybrid_ai(escolhe_o_modelo)

      rodar

      expect(ai_calls.size).to eq(1)
    end

    it 'a citação gravada que não confere com a conversa de agora não vira mensagem' do
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: escolha_gravada.merge('open_loop_source' => 'frase que nunca foi dita nesta conversa'))
      stub_crm_hybrid_ai

      result = nil
      expect { result = rodar }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(ai_calls).to be_empty
    end
  end

  describe 'modelo do tipo (retorno) quando nenhum aprovado serve' do
    let(:checagem) { instance_double(Whatsapp::Templates::DispatchCheck) }
    let(:nome_do_tipo) { "c2y_retorno_#{scenario[:inbox].id}" }
    let(:modelo_do_tipo) do
      { 'id' => 'id_tipo', 'name' => nome_do_tipo, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá, {{1}}! Aqui é da {{2}}. Voltamos ao seu pedido {{3}}, como combinado.' }] }
    end

    def aprovar_o_modelo_do_tipo
      channel = scenario[:inbox].channel
      channel.update_columns(message_templates: [CrmHybridHelpers::APPROVED_TEMPLATE, modelo_do_tipo]) # rubocop:disable Rails/SkipsModelValidations
      WhatsappTemplateProfile.create!(account: scenario[:account], inbox: scenario[:inbox], waba_id: channel.waba_id,
                                      name: nome_do_tipo, language: 'pt_BR', fields: tipo_campos, system_owner: 'fora_da_janela')
      conferir_na_meta
      follow_up.reload # a conversa do follow-up relê a lista de modelos da caixa
    end

    def conferir_na_meta
      verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: nil, template: modelo_do_tipo,
                                                                details: { lookup_source: 'meta' })
      allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(checagem)
      allow(checagem).to receive(:call).and_return(verdict)
    end

    it 'com o modelo do tipo aprovado: envia por ele, com os campos do card, e grava o registro do envio' do
      aprovar_o_modelo_do_tipo
      stub_crm_hybrid_ai(recusa_sem_modelo)

      result = nil
      expect { result = rodar }.to change(Message, :count).by(1).and change(WhatsappOutOfWindowSend, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_calls.size).to eq(1)
      expect(follow_up.reload.metadata).to include('template_name' => nome_do_tipo, 'template_category' => 'utility',
                                                   'send_mode' => 'template')
      expect(follow_up.metadata['template_processed_params']['body'].keys).to eq(%w[1 2 3])
      expect(follow_up.metadata).not_to include('delivery_transport')
      expect(WhatsappOutOfWindowSend.last).to have_attributes(crm_follow_up_id: follow_up.id, tipo: 'retorno', template_name: nome_do_tipo,
                                                              categoria: 'UTILITY', message_id: follow_up.metadata['sent_message_id'])
    end

    it 'com o pré-voo gravado: reusa a composição que recusou e envia pelo modelo, sem chamar a IA' do
      aprovar_o_modelo_do_tipo
      seed_crm_hybrid_transcript(scenario)
      gravar_marca(composicao: recusa_sem_modelo,
                   candidatos: [['native', 'retomada_orcamento', nil, 'pt_BR'], ['native', nome_do_tipo, nil, 'pt_BR']])
      stub_crm_hybrid_ai

      result = rodar

      expect(result.status).to eq(:sent)
      expect(ai_calls).to be_empty
      expect(follow_up.reload.metadata['template_name']).to eq(nome_do_tipo)
    end

    context 'with the hybrid ready' do
      let(:hybrid) { true }

      it 'o modelo do tipo vem ANTES do texto livre pelo Híbrido (ordem do #1585)' do
        aprovar_o_modelo_do_tipo
        stub_crm_hybrid_ai(recusa_sem_modelo)

        result = rodar

        expect(result.status).to eq(:sent)
        expect(ai_calls.size).to eq(1)
        expect(follow_up.reload.metadata).not_to include('delivery_transport')
      end

      it 'sem modelo do tipo aprovado: segue para o texto livre pelo Híbrido, como antes' do
        stub_crm_hybrid_ai(recusa_sem_modelo, crm_hybrid_ai_answer)

        result = rodar

        expect(result.status).to eq(:sent)
        expect(ai_call_modes).to eq(%w[choose_template free_form])
        expect(follow_up.reload.metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'template_declined')
      end
    end

    it 'sem modelo do tipo e sem Híbrido: lembrete na tela, com o motivo do ponto único' do
      stub_crm_hybrid_ai(recusa_sem_modelo)

      result = nil
      expect { result = rodar }.not_to change(Message, :count)

      expect(result).to have_attributes(status: :fallback, error: 'no_template')
    end

    it 'a conferência na Meta recusa o modelo (em análise de novo): lembrete na tela com o motivo, nada vai ao cliente' do
      aprovar_o_modelo_do_tipo
      verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: 'template_not_approved', source: nil, template: nil, details: {})
      allow(checagem).to receive(:call).and_return(verdict)
      stub_crm_hybrid_ai(recusa_sem_modelo)

      result = nil
      expect { result = rodar }.not_to change(Message, :count)

      expect(result).to have_attributes(status: :fallback, error: 'template_not_approved')
    end
  end
end
