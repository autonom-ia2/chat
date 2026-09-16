require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe 'Email reputation API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }
  let(:campaign) do
    EmailCampaign.create!(account: account, sender_identity: identity, name: 'Paused', subject: 'Hello', body_html: '<p>Hello</p>',
                          status: :paused, pause_reason: { kind: 'manual', code: 'manual_pause' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/email_campaigns" }
  let(:collector) do
    instance_double(EmailCampaigns::Reputation::Metrics,
                    call: { sent: 100, permanent: 0, bounced: 0, complaints: 0 }, harmful_feedback_fingerprint: 'original')
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_return(collector)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'retains the successful campaign response shape and resumes a manual pause' do
    post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('id' => campaign.id, 'status' => 'sending', 'pause_reason' => {})
  end

  it 'returns a machine code plus protection and refreshes persisted metrics when resume is denied' do
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'old' } })
    allow(collector).to receive(:call).and_return(sent: 100, permanent: 10, bounced: 10, complaints: 0)
    post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'email_campaign.protected')
    expect(response.parsed_body.dig('protection', 'resume_allowed')).to be(false)
    expect(EmailReputationState.find_by!(account_id: account.id).current_metrics['permanent']).to eq(10)
    expect(campaign.reload).to be_paused
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
  end

  it 'releases a safe guarded resume and clears only the tenant pause flag' do
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'old' }, unrelated: 'keep' })
    post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.reload.internal_attributes).to eq('unrelated' => 'keep')
    expect(EmailReputationAudit.where(account: account, action: 'released').count).to eq(1)
  end

  it 'provides authorized account and campaign re-evaluation without silently resuming' do
    post "#{url}/reputation/reevaluate", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('protection', 'current_metrics', 'sent')).to eq(100)
    post "#{url}/campaigns/#{campaign.id}/reevaluate", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(campaign.reload).to be_paused
  end

  it 'denies an ordinary administrator an override even when params claim SuperAdmin' do
    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    post "#{url}/reputation/override", headers: admin.create_new_auth_token,
                                       params: { reason: 'Reviewed list source', duration_seconds: 60, message_budget: 1,
                                                 type: 'SuperAdmin', actor_id: admin.id, role: 'super_admin' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(EmailReputationAudit.where(account: account, action: 'override_granted')).to be_empty
  end

  it 'enforces campaign tenant isolation and denies ordinary agents re-evaluation' do
    other = create(:account)
    other_identity = EmailSenderIdentity.create!(account: other, domain: 'other.example.com', status: :verified)
    foreign = EmailCampaign.create!(account: other, sender_identity: other_identity, name: 'Foreign')
    post "#{url}/campaigns/#{foreign.id}/reevaluate", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    agent = create(:user, account: account, role: :agent)
    get '/api/v1/profile', headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    post "#{url}/reputation/reevaluate", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'accepts an actual SuperAdmin and audits the bounded override without clearing the rollback flag' do
    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'old' } })
    post "#{url}/reputation/override", headers: super_admin.create_new_auth_token,
                                       params: { reason: 'Reviewed list source', duration_seconds: 60, message_budget: 2 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('protection', 'override_active')).to be(true)
    expect(EmailReputationAudit.find_by!(account: account, action: 'override_granted').actor_id).to eq(super_admin.id)
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
  end

  it 'prevents campaign deletion from erasing reputation history or an ambiguous claim' do
    campaign.email_campaign_recipients.create!(email: 'claimed@example.com', status: :sent)
    delete "#{url}/campaigns/#{campaign.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.delivery_history_retained')
    expect(campaign.reload.email_campaign_recipients.count).to eq(1)
  end

  %w[shadow warning].each do |mode|
    it "does not enqueue delivery on protected legacy resume in #{mode}" do
      allow(collector).to receive(:call).and_return(sent: 100, permanent: 0, transient: 6, bounced: 6, complaints: 0)
      with_modified_env('EMAIL_REPUTATION_MODE' => mode) do
        expect do
          post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
        end.not_to have_enqueued_job(EmailCampaigns::DeliveryJob)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig('protection', 'resume_allowed')).to be(false)
        expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
      end
    end
  end

  it 'redacts operator details and denies audit access to an authenticated ordinary administrator' do
    other = create(:account)
    EmailReputationAudit.create!(account: other, action: 'paused', snapshot: { reason: 'other tenant private' })
    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'legacy internal note' } })
    EmailCampaigns::Reputation::Evaluator.new(account).override!(actor: super_admin, reason: 'Private operator investigation',
                                                                 duration_seconds: 60, message_budget: 2)
    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/Private operator|legacy internal|actor_id|message_budget|feedback_fingerprint|history/)
    post "#{url}/reputation/reevaluate", headers: admin.create_new_auth_token, as: :json
    expect(response.body).not_to match(/actor_id|message_budget|feedback_fingerprint|Private operator/)
    get "#{url}/reputation/history", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/reputation/history", headers: super_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Private operator investigation')
    expect(response.body).not_to include('other tenant private')
  end

  it 'reports resume unavailable while the global provider is blocked and denies tenant release' do
    EmailReputationState.create!(account: account, level: 'healthy')
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(kind: 'provider', code: 'provider_blocked')
    get "#{url}/reputation", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('state', 'resume_allowed')).to be(false)
    expect(EmailCampaigns::Reputation::ProviderRelease).not_to receive(:new)
    post "#{url}/reputation/provider_release", headers: admin.create_new_auth_token,
                                               params: { reason: 'Reviewed remediation', type: 'SuperAdmin' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(EmailReputationAudit.where(action: 'provider_released')).to be_empty
  end

  it 'allows a bounded SuperAdmin exception to resume an active legacy pause while retaining protection' do
    super_admin = create(:user, type: 'SuperAdmin', account: account, role: :administrator)
    allow(collector).to receive(:call).and_return(sent: 100, permanent: 0, transient: 6, bounced: 6, complaints: 0)
    with_modified_env('EMAIL_REPUTATION_MODE' => 'warning') do
      post "#{url}/reputation/override", headers: super_admin.create_new_auth_token,
                                         params: { reason: 'Reviewed remediation plan', duration_seconds: 60, message_budget: 2 }, as: :json
      expect(response).to have_http_status(:ok)
      expect do
        post "#{url}/campaigns/#{campaign.id}/resume", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)
      expect(response).to have_http_status(:ok)
      expect(EmailReputationState.find_by!(account: account).blocked).to be(true)
      expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
    end
  end

  it 'routes actual SuperAdmin provider release through fresh simulated telemetry and records the global audit' do
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
      expect(EmailReputationAudit.find_by!(provider_key: config.provider_key, action: 'provider_released').actor_id).to eq(super_admin.id)
    end
  end
end
