require 'rails_helper'

# Follow-up de IA com dados reais (#1336), no runner de verdade: a IA é simulada só no client (o compositor roda).
# Fora das 24h, a variável ligada ao catálogo vai com o valor do card, e o valor real vence o que a IA devolver.
RSpec.describe Crm::FollowUps::AutoFollowupRunner do
  include CrmHybridHelpers
  include CrmRealValuesHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  before do
    travel_to Time.utc(2026, 9, 14, 15)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  let(:hybrid) { false }
  let(:templates) { [CrmRealValuesHelpers::COBRANCA, CrmRealValuesHelpers::LIVRE] }
  let!(:scenario) { build_real_values_scenario(templates: templates, hybrid: hybrid) }
  let!(:follow_up) { create_crm_hybrid_follow_up(scenario) }
  let(:state) { scenario[:card].reload.metadata.dig('ai', 'auto_followup_state') }

  def run_touch
    seed_crm_hybrid_transcript(scenario)
    described_class.new(follow_up: follow_up, now: Time.current).perform
  end

  it 'sends the template with the real card values, overriding what the AI wrote for the linked positions' do
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)

    result = nil
    expect { result = run_touch }.to change(Message, :count).by(1)

    expect(result.status).to eq(:sent)
    expect(follow_up.reload.metadata['template_processed_params']).to eq(CrmRealValuesHelpers::REAL_PARAMS)
    message = Message.find(follow_up.metadata['sent_message_id'])
    expect(message.additional_attributes.dig('template_params', 'processed_params')).to eq(CrmRealValuesHelpers::REAL_PARAMS)
  end

  it 'offers the AI the body already filled, asking only for the unlinked position, with the same prompt' do
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)

    run_touch

    offered = JSON.parse(ai_calls.first[:input]).fetch('candidates').first
    expect(offered).to include('body' => CrmRealValuesHelpers::FILLED_BODY, 'variables' => ['4'])
    expect(offered).not_to have_key('filled')
  end

  it 'keeps the composer instructions identical to the flag off' do
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)
    run_touch
    with_flag = ai_calls.first[:instructions]

    scenario[:account].disable_features!(CrmRealValuesHelpers::FLAG)
    follow_up.update!(status: :pending, metadata: { 'source' => 'ai_followup', 'touch' => 1, 'message_body' => 'rascunho' })
    scenario[:card].update!(metadata: {})
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)
    described_class.new(follow_up: follow_up.reload, now: Time.current).perform

    expect(ai_calls.first[:instructions]).to eq(with_flag)
  end

  it 'never offers a template whose linked field has no real value' do
    scenario[:card].update!(value_cents: 0)
    stub_crm_hybrid_ai(crm_hybrid_ai_answer('chosen_template' => pick(0, 'retomada_livre'), 'message_body' => '',
                                            'template_variables' => [{ 'position' => '1', 'value' => 'Lead' }]))

    run_touch

    offered = JSON.parse(ai_calls.first[:input]).fetch('candidates')
    expect(offered.pluck('name')).to eq(['retomada_livre'])
    expect(follow_up.reload.metadata['template_name']).to eq('retomada_livre')
  end

  context 'when no template is left after the real values' do
    let(:templates) { [CrmRealValuesHelpers::COBRANCA] }

    before { scenario[:card].update!(value_cents: 0) }

    it 'skips with no_template when there is no WhatsApp Híbrido' do
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('should_send' => false, 'confidence' => 0.2, 'message_body' => '',
                                              'decline_reason' => 'no_fitting_template'))

      result = nil
      expect { result = run_touch }.not_to change(Message, :count)

      expect(result.status).to eq(:skipped)
      expect(JSON.parse(ai_calls.first[:input]).fetch('candidates')).to eq([])
      expect(state).to include('stopped_reason' => 'no_template')
    end

    context 'with WhatsApp Híbrido ready' do
      let(:hybrid) { true }

      it 'goes straight to free text, as with no approved template' do
        stub_crm_hybrid_ai(crm_hybrid_ai_answer)

        expect(run_touch.status).to eq(:sent)
        expect(ai_call_modes).to eq(['free_form'])
        expect(follow_up.reload.metadata).to include('hybrid_free_form_reason' => 'no_candidates', 'send_mode' => 'session')
      end
    end
  end

  it 'keeps the AI values with the flag off' do
    scenario[:account].disable_features!(CrmRealValuesHelpers::FLAG)
    stub_crm_hybrid_ai(pick_cobranca_inventing_values)

    run_touch

    expect(follow_up.reload.metadata['template_processed_params']).to eq(CrmRealValuesHelpers::AI_PARAMS)
  end
end
