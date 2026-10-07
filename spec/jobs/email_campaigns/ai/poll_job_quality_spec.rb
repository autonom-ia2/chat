require 'rails_helper'

# Quality check after the AI e-mail is ready (#1076): one repair round, then fail on what blocks the send
# and keep the rest as warnings; the identity used is recorded on the campaign.
RSpec.describe EmailCampaigns::Ai::PollJob, :aggregate_failures do
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let!(:token) { campaign.ai_begin!.tap { |value| campaign.ai_attach_response!(value, 'resp_1') } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient, delete: true) }
  let(:font) { 'font-family="Arial, Helvetica, sans-serif"' }
  let(:identity) { { 'kit_id' => 7, 'name' => 'Hub2You', 'mode' => 'light', 'source' => 'kit' } }
  let(:options) { { 'brand_identity' => identity, 'placeholders' => [] } }

  def email(text_color: '#0b243f', footers: 1)
    footer = EmailCampaigns::LockedFooter::MJML * footers
    '<mjml><mj-body><mj-section background-color="#ffffff"><mj-column>' \
      "<mj-text #{font} font-size=\"16px\" color=\"#{text_color}\">Olá</mj-text></mj-column></mj-section>#{footer}</mj-body></mjml>"
  end

  def completed(mjml)
    { status: 'completed', model: 'gpt-6.1-sol', usage: { 'input_tokens' => 10, 'output_tokens' => 10 },
      text: { subject: 'Oi', preheader: 'Prévia', subject_variants: %w[a b c], mjml: mjml }.to_json }
  end

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:ready)
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:failed)
  end

  it 'saves a clean e-mail with the identity it used and no warnings' do
    allow(client).to receive(:retrieve).with('resp_1').and_return(completed(email))

    described_class.perform_now(campaign.id, token, 'resp_1', 0, options)

    expect(campaign.reload).to have_attributes(ai_status: 'ready', brand_identity: identity, ai_quality_warnings: [])
    expect(EmailCampaigns::Ai::Broadcaster).to have_received(:ready)
  end

  it 'asks the model once to fix a failing e-mail, with the report, and follows the new request' do
    allow(client).to receive(:retrieve).with('resp_1').and_return(completed(email(text_color: '#c0c0c0')))
    allow(client).to receive(:create_background).and_return(id: 'resp_fix', status: 'queued')

    expect { described_class.perform_now(campaign.id, token, 'resp_1', 0, options) }
      .to have_enqueued_job(described_class).with(campaign.id, token, 'resp_fix', 1, options.merge('repaired' => true))

    expect(client).to have_received(:create_background) do |**request|
      expect(request[:instructions]).to eq(EmailCampaigns::Ai::PromptBuilder.repair)
      expect(request[:input].first[:content].first[:text]).to include('contrast', '#c0c0c0 on #ffffff')
      expect(request[:schema]).to eq(EmailCampaigns::Ai::Generator::GENERATE_SCHEMA)
    end
    expect(campaign.reload).to have_attributes(ai_status: 'processing', ai_provider_response_id: 'resp_fix')
    expect(client).to have_received(:delete).with('resp_1')
  end

  it 'opens only one repair when two ticks see the same ready response' do
    allow(client).to receive(:retrieve).and_return(completed(email(text_color: '#c0c0c0')))
    allow(client).to receive(:create_background).and_return({ id: 'resp_fix', status: 'queued' }, { id: 'resp_fix_2', status: 'queued' })

    described_class.perform_now(campaign.id, token, 'resp_1', 0, options)
    described_class.perform_now(campaign.id, token, 'resp_1', 0, options)

    expect(campaign.reload.ai_provider_response_id).to eq('resp_fix')
    expect(client).to have_received(:delete).with('resp_fix_2')
  end

  it 'keeps what still fails after the repair as warnings for the person' do
    allow(client).to receive(:retrieve).with('resp_1').and_return(completed(email(text_color: '#c0c0c0')))

    described_class.perform_now(campaign.id, token, 'resp_1', 0, options.merge('repaired' => true))

    campaign.reload
    expect(campaign.ai_status).to eq('ready')
    expect(campaign.ai_quality_warnings.pluck('check')).to eq(['contrast'])
  end

  it 'fails with a clear code when the repaired e-mail still cannot be sent (two footers)' do
    allow(client).to receive(:retrieve).with('resp_1').and_return(completed(email(footers: 2)))

    described_class.perform_now(campaign.id, token, 'resp_1', 0, options.merge('repaired' => true))

    expect(campaign.reload).to have_attributes(ai_status: 'failed', ai_error: 'quality_gate_failed')
    expect(EmailCampaigns::Ai::Broadcaster).to have_received(:failed)
  end

  it 'still finishes a generation enqueued before #1076 (no options)' do
    allow(client).to receive(:retrieve).with('resp_1').and_return(completed(email))

    described_class.perform_now(campaign.id, token, 'resp_1', 0)

    expect(campaign.reload).to have_attributes(ai_status: 'ready', brand_identity: {})
  end
end
