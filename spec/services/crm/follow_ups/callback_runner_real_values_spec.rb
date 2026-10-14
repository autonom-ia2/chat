require 'rails_helper'

# Retorno agendado (callback) com dados reais (#1336): mesma regra do follow-up de IA, no runner de verdade, com a IA
# simulada só no client.
RSpec.describe Crm::FollowUps::CallbackRunner do
  include CrmHybridHelpers
  include CrmRealValuesHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  before { travel_to Time.utc(2026, 9, 14, 15) }

  let(:hybrid) { false }
  let(:templates) { [CrmRealValuesHelpers::COBRANCA, CrmRealValuesHelpers::LIVRE] }
  let!(:scenario) { build_real_values_scenario(templates: templates, hybrid: hybrid) }
  let!(:follow_up) do
    create_crm_hybrid_follow_up(scenario, source: 'ai_callback',
                                          metadata: { 'requested_at_text' => 'na próxima terça às 8h', 'callback_retries' => 0 })
  end

  def run_callback
    seed_crm_hybrid_transcript(scenario)
    described_class.new(follow_up: follow_up, now: Time.current).perform
  end

  it 'sends the template with the real card values, overriding what the AI wrote for the linked positions' do
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)

    result = nil
    expect { result = run_callback }.to change(Message, :count).by(1)

    expect(result.status).to eq(:sent)
    expect(follow_up.reload.metadata['template_processed_params']).to eq(CrmRealValuesHelpers::REAL_PARAMS)
    message = Message.find(follow_up.metadata['sent_message_id'])
    expect(message.additional_attributes.dig('template_params', 'processed_params')).to eq(CrmRealValuesHelpers::REAL_PARAMS)
    offered = JSON.parse(ai_calls.first[:input]).fetch('candidates').first
    expect(offered).to include('body' => CrmRealValuesHelpers::FILLED_BODY, 'variables' => ['4'])
  end

  it 'never offers a template whose linked field has no real value' do
    scenario[:card].update!(expected_close_at: nil)
    stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => pick(0, 'retomada_livre'), 'message_body' => '',
                                            'template_variables' => [{ 'position' => '1', 'value' => 'Lead' }]))

    expect(run_callback.status).to eq(:sent)
    expect(JSON.parse(ai_calls.first[:input]).fetch('candidates').pluck('name')).to eq(['retomada_livre'])
  end

  context 'when no template is left after the real values' do
    let(:templates) { [CrmRealValuesHelpers::COBRANCA] }

    before { scenario[:card].update!(value_cents: 0) }

    it 'turns into a reminder (no_template) when there is no WhatsApp Híbrido' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('should_send' => false, 'confidence' => 0.2, 'message_body' => '',
                                              'decline_reason' => 'no_fitting_template'))

      result = nil
      expect { result = run_callback }.not_to change(Message, :count)

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('no_template')
      expect(JSON.parse(ai_calls.first[:input]).fetch('candidates')).to eq([])
    end

    context 'with WhatsApp Híbrido ready' do
      let(:hybrid) { true }

      it 'goes straight to free text, as with no approved template' do
        stub_crm_hybrid_ai(crm_hybrid_ai_answer)

        expect(run_callback.status).to eq(:sent)
        expect(ai_call_modes).to eq(['free_form'])
        expect(follow_up.reload.metadata).to include('hybrid_free_form_reason' => 'no_candidates')
      end
    end
  end

  it 'keeps the AI values with the flag off' do
    scenario[:account].disable_features!(CrmRealValuesHelpers::FLAG)
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)

    run_callback

    expect(follow_up.reload.metadata['template_processed_params']).to eq(CrmRealValuesHelpers::AI_PARAMS)
  end
end
