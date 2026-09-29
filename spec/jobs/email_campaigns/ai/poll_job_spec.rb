require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::PollJob do
  let(:account) { create(:account) }
  let(:campaign) do
    instance_double(EmailCampaign, account: account, ai_processing?: true, ai_generation_token: 'generation', ai_succeed!: true)
  end
  let(:client) { instance_double(Crm::Ai::ResponsesClient, retrieve: result, delete: true) }
  let(:result) do
    { status: 'completed', model: 'gpt-5.6-sol', text: { mjml: '<mjml>old generation</mjml>' }.to_json,
      usage: { 'input_tokens' => 1000, 'output_tokens' => 100 } }
  end

  before do
    allow(EmailCampaign).to receive(:find_by).with(id: 123).and_return(campaign)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    sanitizer = instance_double(EmailCampaigns::Ai::Sanitizer, perform: '<mjml>safe</mjml>')
    allow(EmailCampaigns::Ai::Sanitizer).to receive(:new).and_return(sanitizer)
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:ready)
  end

  it 'prices an in-flight old generation using its actual model after the default changes' do
    expect(Crm::Ai::Config::MODEL_EMAIL).to eq('gpt-6-sol')
    expect(EmailCampaigns::Ai::Broadcaster).to receive(:ready).with(campaign).ordered
    expect(client).to receive(:delete).with('resp_old').ordered

    expect { described_class.perform_now(123, 'generation', 'resp_old', 0) }.to change(Crm::AiUsageEvent, :count).by(1)

    event = Crm::AiUsageEvent.last
    expect(event.model).to eq('gpt-5.6-sol')
    expect(event.cost_estimate.to_f).to be_within(1e-9).of(0.006)
  end

  it 'does not charge twice when another polling job already persisted the generation' do
    allow(campaign).to receive(:ai_succeed!).and_return(false)

    expect { described_class.perform_now(123, 'generation', 'resp_old', 0) }.not_to change(Crm::AiUsageEvent, :count)
    expect(EmailCampaigns::Ai::Broadcaster).not_to have_received(:ready)
  end

  it 'broadcasts a won failure before deleting the retained response' do
    allow(client).to receive(:retrieve).and_return(status: 'failed', error: 'provider failed')
    allow(campaign).to receive(:ai_fail!).and_return(true)
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:failed)
    expect(EmailCampaigns::Ai::Broadcaster).to receive(:failed).with(campaign).ordered
    expect(client).to receive(:delete).with('resp_failed').ordered

    described_class.perform_now(123, 'generation', 'resp_failed', 0)
  end
end
