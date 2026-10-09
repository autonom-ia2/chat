require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Evaluator do
  let(:account) { create(:account) }
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:service) { described_class.new(account, policy: policy) }
  let(:metrics) do
    { sent: 100, permanent: 5, bounced: 5, complaints: 0, transient: 0, unknown: 0, provider_prevented: 0 }
  end
  let(:collector) { instance_double(EmailCampaigns::Reputation::Metrics, call: metrics, harmful_feedback_fingerprint: 'original') }

  before do
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_return(collector)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'publishes harmful local reputation as diagnostic high risk without blocking delivery' do
    result = service.evaluate!
    state = EmailReputationState.find_by!(account_id: account.id)

    expect(result).to include(blocked: false, level: 'high_risk', resume_allowed: true, override_active: false)
    expect(result[:current_metrics]).to include('policy_pause' => true, 'pause' => false, 'resume_allowed' => true)
    expect(state).to have_attributes(blocked: false, level: 'high_risk')
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_nil
  end

  it 'retires a historical tenant latch without erasing its immutable trigger or unrelated account attributes' do
    trigger = { triggered_at: 2.days.ago.change(usec: 0).iso8601, code: 'legacy_pause', metrics: nil, policy: nil }
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused', triggered_at: Time.iso8601(trigger[:triggered_at]),
                                         trigger_snapshot: trigger, override: { expires_at: 1.hour.from_now.iso8601, remaining: 2 })
    account.update!(internal_attributes: { 'other' => 'retained', 'email_campaigns_paused' => { 'reason' => 'legacy' } })

    result = service.evaluate!

    expect(result).to include(blocked: false, override_active: false, resume_allowed: true)
    expect(state.reload).to have_attributes(blocked: false)
    expect(state.trigger_snapshot).to eq(trigger.deep_stringify_keys)
    expect(state.override).to eq({})
    expect(account.reload.internal_attributes).to eq('other' => 'retained')
    expect(EmailReputationAudit.where(account: account, action: 'tenant_protection_retired').count).to eq(1)
  end

  %w[shadow warning enforce].each do |mode|
    it "never turns local reputation into an admission latch in #{mode}" do
      evaluator = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode))
      result = evaluator.evaluate!

      expect(result).to include(blocked: false, resume_allowed: true)
      expect(EmailCampaigns::Guardrail.paused?(account)).to be(false)
      expect(account.reload.internal_attributes['email_campaigns_paused']).to be_nil
    end
  end

  it 'keeps local complaints visible and auditable in warning mode without pausing' do
    allow(collector).to receive(:call).and_return(metrics.merge(sent: 1000, permanent: 0, bounced: 0, complaints: 2))
    warning = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'warning'))

    result = warning.evaluate!

    expect(result).to include(blocked: false, level: 'high_risk', resume_allowed: true)
    expect(result.dig(:current_metrics, 'complaints')).to eq(2)
    expect(result.dig(:current_metrics, 'spam_alert')).to be(true)
    expect(EmailReputationAudit.where(account: account, action: 'risk_alert').count).to eq(1)
  end

  it 'does not publish or block from a superseded local observation and schedules another pass' do
    allow(collector).to receive(:call) do
      EmailCampaigns::Reputation::EvaluationQueue.invalidate(account.id)
      metrics
    end
    allow(EmailCampaigns::Reputation::EvaluationQueue).to receive(:request)

    result = service.evaluate!
    state = EmailReputationState.find_by!(account: account)

    expect(result).to include(blocked: false, resume_allowed: true, current_metrics: {})
    expect(state).to have_attributes(blocked: false, current_metrics: {})
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_nil
    expect(EmailCampaigns::Reputation::EvaluationQueue).to have_received(:request).with(account.id)
  end

  it 'allows compatibility resume regardless of local risk while still honoring provider protection' do
    yielded = false
    result = service.resume! { yielded = true }
    expect(result).to include(blocked: false, resume_allowed: true)
    expect(yielded).to be(true)

    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection)
      .and_return(kind: 'provider', code: 'provider_blocked', overridable: false)
    yielded = false
    result = service.resume! { yielded = true }
    expect(result).to include(resume_allowed: false, protection: include(code: 'provider_blocked'))
    expect(yielded).to be(false)
  end

  it 'retires the tenant override endpoint while preserving SuperAdmin authorization boundaries' do
    admin = create(:user, account: account, role: :administrator)
    super_admin = create(:user, type: 'SuperAdmin')

    expect do
      service.override!(actor: admin, reason: 'Reviewed local risk', duration_seconds: 60, message_budget: 1)
    end.to(raise_error { |error| expect(error.class.name).to eq('Pundit::NotAuthorizedError') })
    expect do
      service.override!(actor: super_admin, reason: 'Reviewed local risk', duration_seconds: 60, message_budget: 1)
    end.to raise_error(CustomExceptions::EmailReputationOverride, 'tenant reputation override retired')
    expect(EmailReputationAudit.where(account: account, action: 'override_granted')).to be_empty
  end

  it 'preserves an existing trigger snapshot and append-only audit database invariants' do
    trigger = { triggered_at: 1.day.ago.change(usec: 0).iso8601, code: 'reputation_threshold', metrics: metrics, policy: policy.snapshot }
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused', triggered_at: Time.iso8601(trigger[:triggered_at]),
                                         trigger_snapshot: trigger)
    audit = EmailReputationAudit.create!(account: account, action: 'paused', snapshot: trigger)

    expect do
      EmailReputationState.transaction(requires_new: true) do
        EmailReputationState.where(id: state.id).update_all(trigger_snapshot: {}) # rubocop:disable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
    expect do
      EmailReputationAudit.transaction(requires_new: true) { EmailReputationAudit.where(id: audit.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it 'publishes the observation generation without changing historical trigger evidence' do
    trigger = { triggered_at: 1.day.ago.change(usec: 0).iso8601, code: 'legacy_pause', metrics: nil, policy: nil }
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused', triggered_at: Time.iso8601(trigger[:triggered_at]),
                                         trigger_snapshot: trigger)

    service.evaluate!
    state.reload

    expect(state.current_metrics.fetch('evaluation_generation')).to eq(state.observation_generation)
    expect(state.trigger_snapshot).to eq(trigger.deep_stringify_keys)
    expect(state.blocked).to be(false)
  end
end
