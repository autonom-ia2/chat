require 'rails_helper'

# #1111: an adjustment that used a site asked for in the request changes the identity of the e-mail only when the
# person applies it; discarding the preview writes nothing.
RSpec.describe 'E-mail campaign AI adjustment identity (#1111)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:old_identity) { { 'kit_id' => 1, 'name' => 'Hub2You', 'mode' => 'light', 'source' => 'kit' } }
  let(:campaign) { create(:email_campaign, account: account, status: :draft, brand_identity: old_identity) }
  let(:site_identity) do
    { 'name' => 'Aurora', 'mode' => 'light', 'source' => 'site', 'source_url' => 'https://aurora.example/',
      'site_request' => { 'host' => 'aurora.example', 'status' => 'used', 'import_id' => 9 } }
  end
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/ai/campaigns/#{campaign.id}/adjustment" }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' }))
  end

  after { EmailCampaigns::Ai::Adjustment.clear(campaign) }

  def propose(brand_identity)
    token = campaign.ai_begin!
    EmailCampaigns::Ai::Adjustment.start(campaign, token: token, request: { base: '<mjml></mjml>', brand_identity: brand_identity })
    EmailCampaigns::Ai::Adjustment.update(campaign, token, status: 'proposed', mjml: '<mjml></mjml>', summary: 'Troquei as cores.')
    campaign.ai_propose!(token)
    token
  end

  it 'shows the site notice with the proposal and records the new identity when the person applies it' do
    token = propose(site_identity)
    expect(EmailCampaigns::Ai::Adjustment.presented(campaign, token)['site_request']).to include('host' => 'aurora.example')

    post "#{path}/apply", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['brand_identity']).to eq(site_identity)
    expect(campaign.reload.brand_identity).to eq(site_identity)
    expect(EmailCampaigns::Ai::Adjustment.find(campaign, token)).to be_nil
  end

  it 'writes nothing when the person discards the preview' do
    token = propose(site_identity)

    delete path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(campaign.reload.brand_identity).to eq(old_identity)
    expect(EmailCampaigns::Ai::Adjustment.find(campaign, token)).to be_nil
  end

  it 'keeps the identity when the adjustment did not use a site' do
    propose('kit_id' => 2, 'name' => 'Outra', 'mode' => 'light', 'source' => 'kit',
            'site_request' => { 'host' => 'aurora.example', 'status' => 'unreadable' })

    post "#{path}/apply", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(campaign.reload.brand_identity).to eq(old_identity)
  end

  it 'ignores an adjustment of an older generation' do
    propose(site_identity)
    campaign.ai_begin!

    post "#{path}/apply", headers: admin.create_new_auth_token, as: :json

    expect(campaign.reload.brand_identity).to eq(old_identity)
  end
end
