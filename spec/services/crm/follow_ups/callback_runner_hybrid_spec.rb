require 'rails_helper'

# Retorno agendado (callback) fora das 24h numa caixa Oficial com WhatsApp Híbrido (chat#1349):
# mesma regra do follow-up de IA. Template primeiro; sem candidato, ou com a IA recusando todos (e sem
# encerramento), o texto livre sai pelo WhatsApp API. Sem Híbrido, segue o fallback de lembrete na tela.
RSpec.describe Crm::FollowUps::CallbackRunner do
  include CrmHybridHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  before { travel_to Time.utc(2026, 9, 14, 15) }

  let!(:scenario) { build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE]) }
  let!(:follow_up) do
    create_crm_hybrid_follow_up(scenario, source: 'ai_callback',
                                          metadata: { 'requested_at_text' => 'na próxima terça às 8h', 'callback_retries' => 0 })
  end

  def run_callback
    seed_crm_hybrid_transcript(scenario)
    described_class.new(follow_up: follow_up, now: Time.current).perform
  end

  def decline_template(**overrides)
    crm_hybrid_ai_answer({ 'should_send' => false, 'message_body' => '', 'confidence' => 0.2,
                           'decline_reason' => 'no_fitting_template' }.merge(overrides))
  end

  context 'without any approved template' do
    let!(:scenario) { build_crm_hybrid_scenario(templates: []) }

    it 'vai direto ao texto livre em uma chamada só e envia pelo WhatsApp API' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      result = nil
      expect { result = run_callback }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(['free_form'])
      expect(ai_calls.first[:instructions]).to include('RETORNO AGENDADO', 'MODO free_form (texto livre permitido nesta conversa):')
      expect(follow_up.reload.metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'no_candidates',
                                                   'send_mode' => 'session')
      expect(Message.find(follow_up.metadata['sent_message_id']).content_attributes)
        .to include('crm_follow_up_id' => follow_up.id, 'crm_follow_up_transport' => 'whatsapp_api')
    end

    it 'falha com whatsapp_api_unavailable e agenda nova tentativa quando o Híbrido cai entre a composição e o envio' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer) { scenario[:connection].update!(status: 'disconnected') }

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error).to eq('whatsapp_api_unavailable')
      expect(follow_up.reload.metadata['callback_retries']).to eq(1)
    end

    it 'barra a citação que não existe na conversa (anti-alucinação)' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('open_loop_source' => 'frase que nunca foi dita nesta conversa'))

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error.to_s).to include('unverified_quote')
    end
  end

  context 'with an approved template' do
    it 'usa o template quando a IA escolhe um que encaixa, sem 2ª chamada' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick,
                                              'template_variables' => [{ 'position' => '1', 'value' => 'Lead' }],
                                              'message_body' => ''))

      result = nil
      expect { result = run_callback }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(['choose_template'])
      expect(follow_up.reload.metadata).to include('template_name' => 'retomada_orcamento', 'send_mode' => 'template')
      expect(follow_up.metadata).not_to include('delivery_transport')
    end

    it 'faz a 2ª chamada em texto livre quando a IA recusa todos os templates' do
      stub_crm_hybrid_ai(decline_template, crm_hybrid_ai_answer)

      result = nil
      expect { result = run_callback }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(%w[choose_template free_form])
      expect(follow_up.reload.metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'template_declined')
      expect(follow_up.metadata).not_to include('template_name')
    end

    it 'never reuses the free text of a failed hybrid attempt as the content of the template sent on retry' do
      free_text = 'Oi! Texto livre que só valia pelo WhatsApp API.'
      stub_crm_hybrid_ai(decline_template, crm_hybrid_ai_answer('message_body' => free_text)) do |call|
        scenario[:connection].update!(status: 'disconnected') if call == 2
      end
      expect(run_callback.error).to eq('whatsapp_api_unavailable')
      expect(follow_up.reload.metadata).to include('message_body' => free_text, 'delivery_transport' => 'whatsapp_api')

      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick, 'message_body' => '',
                                              'template_variables' => [{ 'position' => '1', 'value' => 'Lead' }]))
      result = described_class.new(follow_up: follow_up.reload, now: Time.current).perform

      expect(result.status).to eq(:sent)
      metadata = follow_up.reload.metadata
      expect(metadata).to include('template_name' => 'retomada_orcamento', 'message_body' => Crm::FollowUps::CallbackScheduler::MESSAGE_PLACEHOLDER)
      expect(metadata).not_to include('delivery_transport')
      expect(Message.find(metadata['sent_message_id']).content).not_to include(free_text)
    end

    it 'turns into a reminder without a second call when the refusal is on the merits (nothing_to_send)' do
      stub_crm_hybrid_ai(decline_template('decline_reason' => 'nothing_to_send'))

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('no_template')
      expect(ai_call_modes).to eq(['choose_template'])
    end

    it 'makes the second call when should_send is true but the chosen index is not in the list' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick(7)), crm_hybrid_ai_answer)

      expect(run_callback.status).to eq(:sent)
      expect(ai_call_modes).to eq(%w[choose_template free_form])
    end

    it 'vira lembrete quando a 2ª chamada também recusa' do
      stub_crm_hybrid_ai(decline_template, decline_template)

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('not_composable')
      expect(ai_calls.size).to eq(2)
    end

    it 'vira lembrete no encerramento da 1ª chamada, sem 2ª chamada' do
      stub_crm_hybrid_ai(decline_template('closure_detected' => true))

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('closure')
      expect(ai_calls.size).to eq(1)
    end
  end

  context 'when the hybrid is not available' do
    let!(:scenario) { build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE], hybrid: false) }

    it 'mantém o fallback no_template, sem 2ª chamada' do
      stub_crm_hybrid_ai(decline_template)

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('no_template')
      expect(ai_call_modes).to eq(['choose_template'])
      expect(follow_up.reload.metadata).not_to include('delivery_transport')
    end

    it 'mantém o fallback quando a origem crm_follow_up está desligada na conexão' do
      connection = create_crm_hybrid_connection(account: scenario[:account], inbox: scenario[:inbox], channel: scenario[:inbox].channel)
      connection.update!(disabled_origins: ['crm_follow_up'])
      stub_crm_hybrid_ai(decline_template)

      expect(run_callback.error).to eq('no_template')
      expect(ai_calls.size).to eq(1)
    end
  end
end
