require 'rails_helper'

# Epic integration spec path is assigned to the reports workstream.
RSpec.describe Api::V1::Accounts::EmailCampaigns::ReportsController, type: :controller do # rubocop:disable RSpec/SpecFilePathFormat
  render_views

  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    sign_in(admin)
  end

  it 'preserves legacy recipient fields and provides machine presentation plus full pagination metadata' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :failed)
    get :recipients, params: { account_id: account.id, id: campaign.id, q: row.email, problem: 'true' }, format: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload['recipients'].first).to include(
      'id' => row.id, 'status' => 'failed', 'opens' => 0, 'clicks' => 0, 'preflight_status' => 'unchecked'
    )
    expect(payload['meta']).to include('count' => 1, 'current_page' => 1, 'per_page' => 50, 'total_pages' => 1)
  end

  %i[recipients export import_issues export_import_issues].each do |action|
    it "denies cross-account #{action} without disclosing PII" do
      foreign = create(:email_campaign)
      create(:email_campaign_recipient, email_campaign: foreign, email: 'private@example.org')
      get action, params: { account_id: account.id, id: foreign.id }, format: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('private@example.org')
      expect(response.parsed_body).to eq('error' => 'email_campaign.not_found')
    end

    it "denies agent #{action}" do
      sign_in(create(:user, account: account, role: :agent))
      get action, params: { account_id: account.id, id: campaign.id }, format: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'returns machine 422 JSON before export headers for malformed filters' do
    [{ status: 'bogus' }, { problem: 'maybe' }, { page: 0 }, { page: -1 }, { status: ['bounced'] }, { q: { x: 'y' } }].each do |filter|
      get :export, params: { account_id: account.id, id: campaign.id }.merge(filter), format: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq('application/json')
      expect(response.parsed_body).to include('error' => 'email_campaign.invalid_filter')
    end
  end

  it 'rejects nonempty report date filters and accepts blank legacy date fields' do
    get :index, params: { account_id: account.id, since: '2026-01-01' }, format: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('parameter' => 'since')
    get :index, params: { account_id: account.id, since: '', until: '' }, format: :json
    expect(response).to have_http_status(:ok)
  end

  it 'serializes typed recipient timestamps and flat campaign rates through Jbuilder' do
    timestamp = Time.zone.parse('2026-09-16 12:00:00 UTC')
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :sent,
                                            sent_at: timestamp, last_event_at: timestamp, preflight_valid_until: timestamp)
    get :recipients, params: { account_id: account.id, id: campaign.id }, format: :json
    recipient = response.parsed_body.fetch('payload').fetch('recipients').sole
    %w[sent_at last_event_at preflight_valid_until].each do |key|
      expect(Time.iso8601(recipient.fetch(key))).to eq(row.public_send(key))
    end
    get :index, params: { account_id: account.id }, format: :json
    result = response.parsed_body.fetch('payload').fetch('campaigns').sole
    expect(result.slice('open_rate', 'click_rate', 'hard_bounce_rate', 'unsubscribe_rate')).to eq(
      'open_rate' => nil, 'click_rate' => nil, 'hard_bounce_rate' => 0.0, 'unsubscribe_rate' => nil
    )
  end

  it 'serializes database timeline buckets as ISO timestamps' do
    row = create(:email_campaign_recipient, email_campaign: campaign)
    row.email_events.create!(event_type: :delivered, occurred_at: 1.hour.from_now)
    travel_to 2.hours.from_now do
      get :timeline, params: { account_id: account.id, id: campaign.id }, format: :json
      expect(response).to have_http_status(:ok)
      point = response.parsed_body.fetch('payload').fetch('series').sole
      expect(point).to include('delivered' => 1)
      expect(Time.iso8601(point.fetch('bucket'))).to be <= Time.current
    end
  end

  it 'preserves options when selecting a campaign and does not manufacture protection health' do
    other = create(:email_campaign, account: account)
    get :index, params: { account_id: account.id, campaign_id: campaign.id }, format: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload['campaigns'].pluck('id')).to eq([campaign.id])
    expect(payload['campaign_options'].pluck('id')).to contain_exactly(campaign.id, other.id)
    expect(payload['protection']).to include('state' => 'unknown', 'release_eligible' => false)
    expect(payload['preflight']).to include('counts_basis' => 'current_unsent_recipients')
    expect(payload['meta']).to include('count' => 1)
  end

  it 'returns actual import issues with safe summary fields' do
    campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: 'bad@example.org', reason_code: 'duplicate')
    get :import_issues, params: { account_id: account.id, id: campaign.id }, format: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload['issues'].first).to include('raw_email' => 'bad@example.org', 'row_number' => 3, 'reason_code' => 'duplicate')
    expect(payload['preflight']).to include('issues_count' => 1)
    expect(payload['import_summary']).to be_nil
  end

  it 'exports the filtered import issues and neutralizes original row values' do
    campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: ' =example.org', reason_code: 'invalid_email')
    campaign.email_campaign_import_issues.create!(row_number: 4, raw_address: 'excluded@example.org', reason_code: 'duplicate')
    get :export_import_issues, params: { account_id: account.id, id: campaign.id, reason: 'invalid_email' }, format: :json
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    expect(response.body).to include("' =example.org")
    expect(response.body).not_to include('excluded@example.org')
  end

  it 'keeps all authorized options after status/search filters and resolves selected preflight outside the result filter' do
    other = create(:email_campaign, account: account, name: 'Other', status: :paused)
    foreign = create(:email_campaign)
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    get :index, params: { account_id: account.id, campaign_id: campaign.id, campaign_status: 'paused', q: 'Other' }, format: :json
    payload = response.parsed_body.fetch('payload')
    expect(payload['campaigns']).to be_empty
    expect(payload['campaign_options'].pluck('id')).to contain_exactly(campaign.id, other.id)
    expect(payload['preflight']['counts']).to include('total' => 1, 'invalid' => 1)
    expect(payload['campaign_options'].pluck('id')).not_to include(foreign.id)
    expect(payload['protection']['capabilities']['resume']).to be(false)
  end

  it 'does not expose foreign selected preflight, state or option data' do
    foreign = create(:email_campaign)
    create(:email_campaign_recipient, email_campaign: foreign, email: 'private@example.org')
    get :index, params: { account_id: account.id, campaign_id: foreign.id }, format: :json
    payload = response.parsed_body.fetch('payload')
    expect(payload['campaigns']).to be_empty
    expect(payload['preflight']).to be_nil
    expect(payload['protection']['state']).to eq('unknown')
    expect(response.body).not_to include('private@example.org')
  end

  it 'builds report-level protection once independently of the number of campaigns' do
    create_list(:email_campaign, 4, account: account)
    adapter = instance_double(EmailCampaigns::Presentation::Protection)
    expect(EmailCampaigns::Presentation::Protection).to receive(:new).once.with(account: account, actor: admin).and_return(adapter)
    expect(adapter).to receive(:call).once.with(campaign: nil, preflight: nil).and_return(state: 'unknown', release_eligible: false)
    get :index, params: { account_id: account.id }, format: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').fetch('protection')).to include('state' => 'unknown')
  end
end
