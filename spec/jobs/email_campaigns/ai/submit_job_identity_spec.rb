require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::SubmitJob, :aggregate_failures do
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:kit) { create(:brand_kit, account: account, name: 'Hub2You') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient, create_background: { id: 'resp_1', status: 'queued' }) }

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  it 'writes the chosen identity into the prompt and hands its snapshot and the placeholders to the poll' do
    token = campaign.ai_begin!
    params = { 'brief' => 'Convite', 'placeholders' => ['cupom'], 'assets' => [], 'brand' => { 'kit_id' => kit.id, 'mode' => 'light' } }

    expect { described_class.perform_now(campaign.id, token, params) }
      .to have_enqueued_job(EmailCampaigns::Ai::PollJob)
      .with(campaign.id, token, 'resp_1', 0, { 'brand_identity' => { 'kit_id' => kit.id, 'name' => 'Hub2You', 'mode' => 'light', 'source' => 'kit' },
                                               'placeholders' => ['cupom'] })

    expect(client).to have_received(:create_background) do |**request|
      expect(request[:instructions]).to include('<<<IDENTIDADE', '"name":"Hub2You"')
      expect(request[:schema][:schema][:properties][:subject_variants]).to eq(type: 'array', items: { type: 'string' })
    end
  end

  it 'sends the chosen identity to "Ajustar com IA" too (#1095), with the e-mail as blocks' do
    token = campaign.ai_begin!
    base = "<mjml><mj-body>#{EmailAdjustFixture::HERO}#{EmailCampaigns::LockedFooter::MJML}</mj-body></mjml>"
    params = { 'brief' => 'Deixe o botão com a cor da marca', 'placeholders' => [], 'assets' => [], 'base_mjml' => base,
               'brand' => { 'kit_id' => kit.id, 'mode' => 'light' } }

    described_class.perform_now(campaign.id, token, params)

    expect(client).to have_received(:create_background) do |**request|
      expect(request[:schema]).to eq(EmailCampaigns::Ai::EditPromptBuilder::SCHEMA)
      expect(request[:instructions]).to include('<<<IDENTIDADE', '"name":"Hub2You"', 'PRIMARY=#c8102e')
    end
    expect(EmailCampaigns::Ai::Adjustment.find(campaign, token)['instructions']).to include('<<<IDENTIDADE')
  end
end
