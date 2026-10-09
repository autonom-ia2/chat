require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe 'Email reputation API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }
  let(:campaign) do
    EmailCampaign.create!(
      account: account, sender_identity: identity, name: 'Paused', subject: 'Hello',
      body_html: '<p>Hello</p>', status: :paused,
      pause_reason: { kind: 'manual', code: 'manual_pause' }
    )
  end
  let(:url) { "/api/v1/accounts/#{account.id}/email_campaigns" }
  let(:collector) do
    instance_double(
      EmailCampaigns::Reputation::Metrics,
      call: { sent: 100, permanent: 0, transient: 0, unknown: 0, bounced: 0, complaints: 0, provider_prevented: 0 },
      harmful_feedback_fingerprint: 'original'
    )
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_return(collector)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'retains the campaign response shape and resumes a manual pause' do
    campaign.email_campaign_recipients.create!(email: 'next@example.org')

    post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('id' => campaign.id, 'status' => 'sending', 'pause_reason' => nil)
    expect(campaign.reload.pause_reason).to eq({})
  end

  it 'does not block resume from local risk and retires only the legacy tenant flag' do
    campaign.email_campaign_recipients.create!(email: 'next@example.org')
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'old' }, unrelated: 'keep' })
    EmailReputationState.create!(account: account, blocked: true, level: 'high_risk')

    expect do
      post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)

    expect(response).to have_http_status(:ok)
    expect(account.reload.internal_attributes).to eq('unrelated' => 'keep')
    expect(EmailReputationState.find_by!(account: account).blocked).to be(false)
    expect(EmailReputationAudit.where(account: account, action: 'tenant_protection_retired').count).to eq(1)
  end

  it 'keeps local reputation re-evaluation diagnostic and never resumes the campaign implicitly' do
    allow(collector).to receive(:call).and_return(
      sent: 100, permanent: 10, transient: 0, unknown: 0, bounced: 10, complaints: 0, provider_prevented: 0
    )

    post "#{url}/reputation/reevaluate", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('protection', 'blocked')).to be(false)
    expect(response.parsed_body.dig('protection', 'current_metrics', 'permanent')).to eq(10)
    expect(response.parsed_body.dig('protection', 'current_metrics', 'pause')).to be(false)
    expect(campaign.reload).to be_paused
  end

  it 'still denies resume when the global sending protection is active' do
    campaign.email_campaign_recipients.create!(email: 'next@example.org')
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection)
      .and_return(kind: 'provider', code: 'provider_blocked', overridable: false)

    post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'email_campaign.protected')
    expect(response.parsed_body.dig('protection', 'code')).to eq('provider_blocked')
    expect(campaign.reload).to be_paused
  end

  it 'retires tenant overrides while preserving authorization boundaries' do
    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    post "#{url}/reputation/override", headers: admin.create_new_auth_token,
                                       params: { reason: 'Reviewed list source', duration_seconds: 60, message_budget: 1,
                                                 type: 'SuperAdmin' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)
    post "#{url}/reputation/override", headers: super_admin.create_new_auth_token,
                                       params: { reason: 'Reviewed list source', duration_seconds: 60, message_budget: 1 }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.invalid_override')
    expect(EmailReputationAudit.where(account: account, action: 'override_granted')).to be_empty
  end

  it 'enforces campaign tenant isolation and denies ordinary agents re-evaluation' do
    other = create(:account)
    other_identity = EmailSenderIdentity.create!(account: other, domain: 'other.example.com', status: :verified)
    foreign = EmailCampaign.create!(account: other, sender_identity: other_identity, name: 'Foreign')

    post "#{url}/campaigns/#{foreign.id}/reevaluate", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    agent = create(:user, account: account, role: :agent)
    post "#{url}/reputation/reevaluate", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'prevents campaign deletion from erasing delivery history' do
    campaign.email_campaign_recipients.create!(email: 'claimed@example.com', status: :sent)

    delete "#{url}/campaigns/#{campaign.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.delivery_history_retained')
    expect(campaign.reload.email_campaign_recipients.count).to eq(1)
  end

  %w[shadow warning enforce].each do |mode|
    it "allows local reputation risk to remain diagnostic in #{mode}" do
      campaign.email_campaign_recipients.create!(email: 'next@example.org')
      allow(collector).to receive(:call).and_return(
        sent: 100, permanent: 6, transient: 0, unknown: 0, bounced: 6, complaints: 0, provider_prevented: 0
      )

      with_modified_env('EMAIL_REPUTATION_MODE' => mode) do
        post "#{url}/reputation/reevaluate", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('protection', 'blocked')).to be(false)

        expect do
          post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
        end.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)
        expect(response).to have_http_status(:ok)
      end
    end
  end
  it 'redacts private audit details from tenant responses and scopes history to SuperAdmin' do
    other = create(:account)
    EmailReputationAudit.create!(account: other, action: 'risk_alert', snapshot: { reason: 'other tenant private' })
    audit = EmailReputationAudit.create!(account: account, action: 'risk_alert', snapshot: { reason: 'private operator note' })
    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)

    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('private operator note', 'other tenant private', 'actor_id')

    get "#{url}/reputation/history", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "#{url}/reputation/history", headers: super_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(audit.id.to_s, 'private operator note')
    expect(response.body).not_to include('other tenant private')
  end

  it 'reports resume unavailable while global protection is active and denies tenant administrators global release' do
    EmailReputationState.create!(account: account, level: 'healthy')
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection)
      .and_return(kind: 'provider', code: 'provider_blocked', overridable: false)

    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('state', 'resume_allowed')).to be(false)

    post "#{url}/reputation/provider_release", headers: admin.create_new_auth_token,
                                               params: { reason: 'Reviewed remediation', type: 'SuperAdmin' }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps the explicit SuperAdmin provider release as an emergency audited fallback' do
    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)
    ses = instance_double(EmailCampaigns::Ses::Client, get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
    cloudwatch = instance_double(Aws::CloudWatch::Client)
    response_point = Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
      datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: Time.current, average: 0)]
    )
    allow(cloudwatch).to receive(:get_metric_statistics).and_return(response_point)

    with_modified_env('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true', 'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '123456789012') do
      config = EmailCampaigns::Reputation::ProviderConfig.new
      state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true)
      monitor = EmailCampaigns::Reputation::ProviderMonitor.new(config: config, ses: ses, cloudwatch: cloudwatch)
      allow(EmailCampaigns::Reputation::ProviderMonitor).to receive(:new).and_return(monitor)

      post "#{url}/reputation/provider_release", headers: super_admin.create_new_auth_token,
                                                 params: { reason: 'Reviewed provider remediation' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('code' => 'provider_released')
      expect(state.reload.blocked).to be(false)
    end
  end
end
