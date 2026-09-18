require 'rails_helper'

# Epic integration spec path is assigned to the reports workstream.
RSpec.describe Api::V1::Accounts::EmailCampaigns::ReportsController, type: :request do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
  end

  # Exercise the real token-authenticated HTTP stack; session sign_in is not the API contract.
  def report_get(action, params:, format: nil)
    suffix = if action == :index
               ''
             elsif action == :export_import_issues
               "/#{params.fetch(:id)}/import_issues/export"
             else
               "/#{params.fetch(:id)}/#{action}"
             end
    path = "/api/v1/accounts/#{params.fetch(:account_id)}/email_campaigns/reports#{suffix}"
    get path, params: params.except(:account_id, :id), headers: headers, as: (format || :json)
  end

  it 'preserves legacy recipient fields and provides machine presentation plus full pagination metadata' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :failed)
    report_get :recipients, params: { account_id: account.id, id: campaign.id, q: row.email, problem: 'true' }, format: :json
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
      report_get action, params: { account_id: account.id, id: foreign.id }, format: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('private@example.org')
      expect(response.parsed_body).to eq('error' => 'email_campaign.not_found')
    end

    it "denies agent #{action}" do
      report_get action, params: { account_id: account.id, id: campaign.id }, format: :json
      expect(response).to have_http_status(:ok)
      headers.replace(create(:user, account: account, role: :agent).create_new_auth_token)
      report_get action, params: { account_id: account.id, id: campaign.id }, format: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    end
  end

  it 'returns machine 422 JSON before export headers for malformed filters' do
    [{ status: 'bogus' }, { problem: 'maybe' }, { page: 0 }, { page: -1 }, { status: ['bounced'] }, { q: { x: 'y' } }].each do |filter|
      report_get :export, params: { account_id: account.id, id: campaign.id }.merge(filter), format: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq('application/json')
      expect(response.parsed_body).to include('error' => 'email_campaign.invalid_filter')
    end
  end

  it 'rejects nonempty report date filters and accepts blank legacy date fields' do
    report_get :index, params: { account_id: account.id, since: '2026-01-01' }, format: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('parameter' => 'since')
    report_get :index, params: { account_id: account.id, since: '', until: '' }, format: :json
    expect(response).to have_http_status(:ok)
  end

  it 'serializes typed recipient timestamps and flat campaign rates through Jbuilder' do
    timestamp = Time.zone.parse('2026-09-16 12:00:00 UTC')
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :sent,
                                            sent_at: timestamp, last_event_at: timestamp, preflight_valid_until: timestamp)
    report_get :recipients, params: { account_id: account.id, id: campaign.id }, format: :json
    recipient = response.parsed_body.fetch('payload').fetch('recipients').sole
    %w[sent_at last_event_at preflight_valid_until].each do |key|
      expect(Time.iso8601(recipient.fetch(key))).to eq(row.public_send(key))
    end
    report_get :index, params: { account_id: account.id }, format: :json
    result = response.parsed_body.fetch('payload').fetch('campaigns').sole
    expect(result.slice('open_rate', 'click_rate', 'hard_bounce_rate', 'unsubscribe_rate')).to eq(
      'open_rate' => nil, 'click_rate' => nil, 'hard_bounce_rate' => 0.0, 'unsubscribe_rate' => nil
    )
  end

  it 'serializes database timeline buckets as ISO timestamps' do
    row = create(:email_campaign_recipient, email_campaign: campaign)
    row.email_events.create!(event_type: :delivered, occurred_at: 1.hour.from_now)
    travel_to 2.hours.from_now do
      report_get :timeline, params: { account_id: account.id, id: campaign.id }, format: :json
      expect(response).to have_http_status(:ok)
      point = response.parsed_body.fetch('payload').fetch('series').sole
      expect(point).to include('delivered' => 1)
      expect(Time.iso8601(point.fetch('bucket'))).to be <= Time.current
    end
  end

  it 'preserves options when selecting a campaign and does not manufacture protection health' do
    other = create(:email_campaign, account: account, sender_identity: campaign.sender_identity)
    report_get :index, params: { account_id: account.id, campaign_id: campaign.id }, format: :json
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
    report_get :import_issues, params: { account_id: account.id, id: campaign.id }, format: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload['issues'].first).to include('raw_email' => 'bad@example.org', 'row_number' => 3, 'reason_code' => 'duplicate')
    expect(payload['preflight']).to include('issues_count' => 1)
    expect(payload['import_summary']).to be_nil
  end

  it 'exports the filtered import issues and neutralizes original row values' do
    campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: ' =example.org', reason_code: 'invalid_email')
    campaign.email_campaign_import_issues.create!(row_number: 4, raw_address: 'excluded@example.org', reason_code: 'duplicate')
    report_get :export_import_issues, params: { account_id: account.id, id: campaign.id, reason: 'invalid_email' }, format: :json
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    expect(response.body).to include("' =example.org")
    expect(response.body).not_to include('excluded@example.org')
  end

  it 'keeps all authorized options after status/search filters and resolves selected preflight outside the result filter' do
    other = create(:email_campaign, account: account, sender_identity: campaign.sender_identity, name: 'Other', status: :paused)
    foreign = create(:email_campaign)
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    report_get :index, params: { account_id: account.id, campaign_id: campaign.id, campaign_status: 'paused', q: 'Other' }, format: :json
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
    report_get :index, params: { account_id: account.id, campaign_id: foreign.id }, format: :json
    payload = response.parsed_body.fetch('payload')
    expect(payload['campaigns']).to be_empty
    expect(payload['preflight']).to be_nil
    expect(payload['protection']['state']).to eq('unknown')
    expect(response.body).not_to include('private@example.org')
  end

  it 'builds report-level protection once independently of the number of campaigns' do
    create_list(:email_campaign, 4, account: account, sender_identity: campaign.sender_identity)
    adapter = instance_double(EmailCampaigns::Presentation::Protection)
    expect(EmailCampaigns::Presentation::Protection).to receive(:new).once.with(account: account, actor: admin).and_return(adapter)
    expect(adapter).to receive(:call).once.with(campaign: nil, preflight: nil).and_return(state: 'unknown', release_eligible: false)
    report_get :index, params: { account_id: account.id }, format: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').fetch('protection')).to include('state' => 'unknown')
  end
end
