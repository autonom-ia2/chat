require 'rails_helper'

# Follow-up de IA fora das 24h numa caixa Oficial com WhatsApp Híbrido (chat#1349).
# Template primeiro; sem candidato, ou com a IA recusando todos (e sem encerramento), o texto livre
# sai pelo WhatsApp API em uma 2ª chamada. A IA é simulada no nível do client: o compositor roda de verdade.
RSpec.describe Crm::FollowUps::AutoFollowupRunner do
  include CrmHybridHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  before do
    travel_to Time.utc(2026, 9, 14, 15)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  let!(:scenario) { build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE]) }
  let!(:follow_up) { create_crm_hybrid_follow_up(scenario) }
  let(:state) { scenario[:card].reload.metadata.dig('ai', 'auto_followup_state') }

  def run_touch
    seed_crm_hybrid_transcript(scenario)
    described_class.new(follow_up: follow_up, now: Time.current).perform
  end

  def decline_template(**overrides)
    crm_hybrid_ai_answer({ 'should_send' => false, 'message_body' => '', 'confidence' => 0.2,
                           'decline_reason' => 'no_fitting_template' }.merge(overrides))
  end

  context 'without any approved template' do
    let(:scenario) { build_crm_hybrid_scenario(templates: []) }

    it 'goes straight to free text in a single call, with the free_form prompt and no candidates' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      result = nil
      expect { result = run_touch }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(['free_form'])
      expect(JSON.parse(ai_calls.first[:input])).not_to have_key('candidates')
      expect(ai_calls.first[:instructions]).to include('MODO free_form (texto livre permitido nesta conversa):')
      expect(ai_calls.first[:instructions]).not_to include('DENTRO da janela')
    end

    it 'sends a session message (no template) and records the WhatsApp API transport and why' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      run_touch

      metadata = follow_up.reload.metadata
      expect(metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'no_candidates',
                                  'send_mode' => 'session')
      expect(metadata).not_to include('template_name', 'template_category', 'template_processed_params')
      message = Message.find(metadata['sent_message_id'])
      expect(message.content).to eq('Oi! Passando para saber se ainda posso te ajudar com o orçamento.')
      expect(message.content_attributes).to include('crm_follow_up_id' => follow_up.id, 'crm_follow_up_transport' => 'whatsapp_api')
      expect(message.content_attributes).not_to have_key('template_params')
    end

    it 'records on the timeline and in the touch history that it left through WhatsApp API and why' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      run_touch

      touch = state['touches'].last
      expect(touch).to include('outcome' => 'sent', 'mode' => 'free_form', 'transport' => 'whatsapp_api',
                               'hybrid_reason' => 'no_candidates')
      event = scenario[:card].activities.find_by!(event_type: 'ai_followup_sent')
      expect(event.payload).to include('send_mode' => 'free_form', 'delivery_transport' => 'whatsapp_api',
                                       'hybrid_free_form_reason' => 'no_candidates', 'follow_up_id' => follow_up.id)
    end

    it 'really leaves through the WAHA session, with the crm_follow_up origin' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)
      client = instance_double(Waha::Client)
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                        new_message_id: '3EB0FOLLOW', send_text: { 'id' => 'true_5511937016094@c.us_3EB0FOLLOW' },
                                        start_typing: {}, stop_typing: {})
      allow(Kernel).to receive(:sleep)
      Redis::Alfred.delete("whatsapp_hybrid:chat_id:#{scenario[:connection].session_name}:5511937016094")

      run_touch
      message = Message.find(follow_up.reload.metadata['sent_message_id'])
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).to have_received(:send_text).with(hash_including(session: scenario[:connection].session_name,
                                                                      text: message.content, id: '3EB0FOLLOW'))
      expect(message.reload.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'crm_follow_up')
    end

    it 'does not apply the marketing cap to free text' do
      scenario[:account].crm_follow_ups.create!(
        card: scenario[:card], conversation: scenario[:conversation], contact: scenario[:contact], title: 'Toque anterior',
        due_at: 2.hours.ago, timezone: 'UTC', status: :done, automation_mode: :auto_send_message, created_by: scenario[:user],
        metadata: { 'source' => 'ai_followup', 'send_mode' => 'template', 'template_category' => 'marketing',
                    'message_body' => 'anterior', 'sent_at' => 1.hour.ago.iso8601 }
      )
      stub_crm_hybrid_ai(crm_hybrid_ai_answer)

      expect(run_touch.status).to eq(:sent)
    end

    it 'blocks the composition when the quote is not in the conversation (anti-hallucination)' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('open_loop_source' => 'frase que nunca foi dita nesta conversa'))

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error.to_s).to include('unverified_quote')
    end

    it 'recomposes later when the hybrid drops during the AI call, sending nothing' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer) { scenario[:connection].update!(status: 'disconnected') }

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:rescheduled)
      expect(follow_up.reload.due_at).to be > Time.current
      expect(follow_up.metadata).not_to include('delivery_transport')
    end
  end

  context 'with an approved template' do
    def pick_template
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick,
                                              'template_variables' => [{ 'position' => '1', 'value' => 'Lead' }],
                                              'message_body' => ''))
    end

    it 'uses the template when the AI picks one that fits: one call, offered the candidate' do
      pick_template

      result = nil
      expect { result = run_touch }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(['choose_template'])
      expect(JSON.parse(ai_calls.first[:input]).fetch('candidates').size).to eq(1)
    end

    it 'sends the template with no WhatsApp API transport marker anywhere' do
      pick_template

      run_touch

      metadata = follow_up.reload.metadata
      expect(metadata).to include('template_name' => 'retomada_orcamento', 'send_mode' => 'template')
      expect(metadata).not_to include('delivery_transport', 'hybrid_free_form_reason')
      expect(Message.find(metadata['sent_message_id']).content_attributes).not_to have_key('crm_follow_up_transport')
      expect(state['touches'].last).to include('mode' => 'template', 'template_name' => 'retomada_orcamento')
      expect(state['touches'].last).not_to have_key('transport')
    end

    it 'makes a second free text call when the AI declines every template (index -1)' do
      stub_crm_hybrid_ai(decline_template, crm_hybrid_ai_answer)

      result = nil
      expect { result = run_touch }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(ai_call_modes).to eq(%w[choose_template free_form])
      expect(JSON.parse(ai_calls.last[:input])).not_to have_key('candidates')
      expect(follow_up.reload.metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'template_declined')
      expect(follow_up.metadata).not_to include('template_name')
    end

    it 'does NOT make a second call when the refusal is on the merits (nothing_to_send)' do
      stub_crm_hybrid_ai(decline_template('decline_reason' => 'nothing_to_send'))

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:skipped)
      expect(ai_call_modes).to eq(['choose_template'])
      expect(state).to include('spent' => true, 'stopped_reason' => 'no_open_loop')
      expect(follow_up.reload.metadata).to include('decline_reason' => 'nothing_to_send')
      expect(follow_up.metadata).not_to include('delivery_transport')
    end

    it 'makes the second call when should_send is true but the chosen index is not in the list' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick(7)), crm_hybrid_ai_answer)

      expect(run_touch.status).to eq(:sent)
      expect(ai_call_modes).to eq(%w[choose_template free_form])
      expect(follow_up.reload.metadata).to include('delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'template_declined')
    end

    it 'does not make a second call when the template fits but confidence is below the floor' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => crm_hybrid_template_pick,
                                              'confidence' => Crm::Ai::Config::FOLLOWUP_MIN_CONFIDENCE - 0.01))

      expect(run_touch.status).to eq(:skipped)
      expect(ai_call_modes).to eq(['choose_template'])
    end

    it 'never reuses the free text of a failed hybrid attempt as the content of the template sent on retry' do
      free_text = 'Oi! Texto livre que só valia pelo WhatsApp API.'
      stub_crm_hybrid_ai(decline_template, crm_hybrid_ai_answer('message_body' => free_text))
      allow(Crm::FollowUps::MessageSender).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap { |sender| allow(sender).to receive(:whatsapp_api_available?).and_return(false) }
      end
      expect(run_touch.status).to eq(:failed)
      expect(follow_up.reload.metadata).to include('message_body' => free_text, 'delivery_transport' => 'whatsapp_api')

      allow(Crm::FollowUps::MessageSender).to receive(:new).and_call_original
      scenario[:connection].update!(status: 'disconnected')
      pick_template
      result = described_class.new(follow_up: follow_up.reload, now: Time.current).perform

      expect(result.status).to eq(:sent)
      metadata = follow_up.reload.metadata
      expect(metadata).to include('template_name' => 'retomada_orcamento',
                                  'message_body' => Crm::FollowUps::AutoFollowupTouchBuilder::PLACEHOLDER_BODY)
      expect(metadata).not_to include('delivery_transport')
      expect(Message.find(metadata['sent_message_id']).content).not_to include(free_text)
    end

    it 'skips the touch when the second call also declines' do
      stub_crm_hybrid_ai(decline_template, decline_template('decline_reason' => 'none'))

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:skipped)
      expect(ai_calls.size).to eq(2)
      expect(state).to include('spent' => true, 'stopped_reason' => 'no_open_loop')
      expect(follow_up.reload.metadata).not_to include('delivery_transport')
    end

    it 'ends the cadence on closure in the first call, with no second call and no free text' do
      stub_crm_hybrid_ai(decline_template('closure_detected' => true))

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:skipped)
      expect(ai_calls.size).to eq(1)
      expect(state).to include('spent' => true, 'stopped_reason' => 'conversation_closed')
    end

    it 'recomposes later when the hybrid drops after the second composition: never a template with free text' do
      stub_crm_hybrid_ai(decline_template, crm_hybrid_ai_answer) do |call|
        scenario[:connection].update!(status: 'disconnected') if call == 2
      end

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:rescheduled)
      expect(follow_up.reload.metadata).not_to include('delivery_transport', 'template_name')
    end
  end

  # Sem Híbrido pronto o comportamento é exatamente o de antes: template ou 'no_template'.
  describe 'when the hybrid is not available' do
    def expect_no_template_skip
      stub_crm_hybrid_ai(decline_template)

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:skipped)
      expect(ai_call_modes).to eq(['choose_template'])
      expect(state).to include('stopped_reason' => 'no_template')
      expect(follow_up.reload.metadata).not_to include('delivery_transport')
    end

    context 'without a hybrid connection on the inbox' do
      let(:scenario) { build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE], hybrid: false) }

      it('keeps no_template') { expect_no_template_skip }
    end

    context 'with the account outside the pilot' do
      around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '999999') { example.run } }

      it('keeps no_template') { expect_no_template_skip }
    end

    context 'with the crm_follow_up origin turned off' do
      it 'keeps no_template' do
        scenario[:connection].update!(disabled_origins: ['crm_follow_up'])
        expect_no_template_skip
      end
    end

    context 'with the session disconnected' do
      it 'keeps no_template' do
        scenario[:connection].update!(status: 'disconnected')
        expect_no_template_skip
      end
    end

    context 'without templates and without hybrid' do
      let(:scenario) { build_crm_hybrid_scenario(templates: [], hybrid: false) }

      it('keeps no_template') { expect_no_template_skip }
    end
  end

  it 'does not touch a conversation inside 24h: normal free text, no transport and no second call' do
    inside = build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE], last_inbound_ago: 1.hour.ago)
    inside_follow_up = create_crm_hybrid_follow_up(inside)
    inside[:conversation].messages.incoming.last.update!(content: CrmHybridHelpers::TRANSCRIPT_LINE)
    stub_crm_hybrid_ai(crm_hybrid_ai_answer)

    result = described_class.new(follow_up: inside_follow_up, now: Time.current).perform

    expect(result.status).to eq(:sent)
    expect(ai_call_modes).to eq(['free_form'])
    expect(inside_follow_up.reload.metadata).not_to include('delivery_transport')
  end
end
