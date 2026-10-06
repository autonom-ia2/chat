require 'rails_helper'

# #990 — GET …/campaign_journey/results/email/:id/period?period=7|14|30|all: the numbers of one
# e-mail campaign for a period, behind the same campaign_view gate as the rest of the Resultado.
RSpec.describe 'Campaign journey result period API (#990)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:campaign) { create(:email_campaign, account: account, status: :paused) }

  before do
    create(:email_campaign_recipient, email_campaign: campaign, status: :delivered, sent_at: 2.days.ago)
    old = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 21.days.ago)
    old.email_events.create!(event_type: :bounce, occurred_at: 21.days.ago,
                             payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'General' } })
  end

  def period_path(id = campaign.id, channel: 'email')
    "/api/v1/accounts/#{account.id}/campaign_journey/results/#{channel}/#{id}/period"
  end

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  it 'returns the numbers of each period, "all" by default' do
    counts = %w[7 14 30 all].index_with do |period|
      get period_path, params: { period: period }, headers: headers
      expect(response).to have_http_status(:ok)
      response.parsed_body['payload'].slice('period', 'sent', 'permanent_bounces')
    end
    get period_path, headers: headers

    expect(counts).to eq(
      '7' => { 'period' => '7', 'sent' => 1, 'permanent_bounces' => 0 },
      '14' => { 'period' => '14', 'sent' => 1, 'permanent_bounces' => 0 },
      '30' => { 'period' => '30', 'sent' => 2, 'permanent_bounces' => 1 },
      'all' => { 'period' => 'all', 'sent' => 2, 'permanent_bounces' => 1 }
    )
    expect(response.parsed_body['payload']).to include('period' => 'all', 'since' => nil)
    expect(response.parsed_body['payload'].keys).to match_array(
      %w[period since until sent permanent_bounces temporary_bounces complaints hard_bounce_rate complaint_rate]
    )
  end

  it 'refuses a period outside the list' do
    %w[1 365 ever].each do |period|
      get period_path, params: { period: period }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'campaign_journey.invalid_filter', 'parameter' => 'period')
    end
  end

  it 'lets a campaign_view seat read and refuses an agent without campaign permissions' do
    viewer = User.create!(name: 'Leitor', email: "leitor-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23',
                          confirmed_at: Time.current)
    AccountUser.create!(account: account, user: viewer, role: :agent,
                        custom_role: create(:custom_role, account: account, permissions: %w[campaign_view]))
    agent, = create_crm_agent(account: account)

    get period_path, params: { period: '7' }, headers: headers(viewer)
    expect(response).to have_http_status(:ok)

    get period_path, params: { period: '7' }, headers: headers(agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'never answers for a campaign of another account nor for a channel without the block' do
    other_account, = create_account_and_user
    other = create(:email_campaign, account: other_account)

    get period_path(other.id), headers: headers
    expect(response).to have_http_status(:not_found)

    inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    whatsapp = create(:campaign, account: account, inbox: inbox, title: 'Renovação', campaign_type: :one_off,
                                 template_params: { 'name' => 'renovacao' })

    get period_path(whatsapp.display_id, channel: 'whatsapp_official'), headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
