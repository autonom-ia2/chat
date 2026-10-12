require 'rails_helper'

# #1329: a campaign paused before going out — shown in the result and in the overview, resumed by API.
RSpec.describe 'Campaign journey campaign pauses API (#1329)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:campaign) do
    create(:campaign, account: account, inbox: channel.inbox, title: 'Renovação', audience: [], template_params: journey_template_params,
                      message: 'Olá', scheduled_at: 1.hour.ago)
  end
  let!(:pause) do
    CampaignPauses::Pauser.new(campaign, source: 'template', reason_code: 'template_not_approved',
                                         details: { template_name: 'renovacao', status: 'PAUSED' }).perform
  end

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def resume(id = pause.id, user: admin)
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaign_pauses/#{id}/resume", headers: headers(user)
  end

  it 'shows the open pause in the campaign result' do
    get "/api/v1/accounts/#{account.id}/campaign_journey/results/whatsapp_official/#{campaign.display_id}", headers: headers

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.dig('payload', 'campaign')
    expect(payload['status']).to eq('active')
    expect(payload['pause']).to include('source' => 'template', 'reason_code' => 'template_not_approved')
    expect(payload['pause']['details']).to include('status' => 'PAUSED')
  end

  it 'lists the paused campaign in the overview, with its pause' do
    get "/api/v1/accounts/#{account.id}/campaign_journey/overview", headers: headers

    row = response.parsed_body.dig('payload', 'campaigns').find { |item| item['name'] == 'Renovação' }
    expect(row).to include('status' => 'active', 'sent' => 0)
    expect(row['pause']).to include('reason_code' => 'template_not_approved')
  end

  it 'keeps listing a paused campaign older than the period' do
    campaign.update!(scheduled_at: 100.days.ago)

    get "/api/v1/accounts/#{account.id}/campaign_journey/overview", params: { days: 7 }, headers: headers

    row = response.parsed_body.dig('payload', 'campaigns').find { |item| item['name'] == 'Renovação' }
    expect(row['pause']).to include('reason_code' => 'template_not_approved')
  end

  it 'resumes the pause, records who resumed and fires the campaign again' do
    expect { resume }.to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob).with(campaign)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'resumed_by_id')).to eq(admin.id)
    expect(pause.reload.resumed_at).to be_present
  end

  it 'answers 422 pause_not_open for a pause already resumed' do
    resume
    resume

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('pause_not_open')
  end

  it 'answers 401 to a user with campaign_view only' do
    viewer = User.create!(name: 'Leitor', email: "leitor-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: viewer, role: :agent,
                        custom_role: create(:custom_role, account: account, permissions: %w[campaign_view]))

    resume(user: viewer)

    expect(response).to have_http_status(:unauthorized)
    expect(pause.reload).to be_open
  end

  it 'answers 404 for a pause of another account' do
    other_account, = create_account_and_user
    other_channel = journey_cloud_channel(other_account)
    other_campaign = create(:campaign, account: other_account, inbox: other_channel.inbox, audience: [], template_params: journey_template_params)
    other = CampaignPauses::Pauser.new(other_campaign, source: 'manual', reason_code: 'manual_pause').perform

    resume(other.id)

    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_open
  end
end
