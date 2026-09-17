require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Evaluator do
  let(:account) { create(:account) }
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:service) { described_class.new(account, policy: policy) }
  let(:metrics) { { sent: 100, permanent: 5, bounced: 5, complaints: 0, transient: 0 } }
  let(:collector) { instance_double(EmailCampaigns::Reputation::Metrics, call: metrics, harmful_feedback_fingerprint: 'original') }
  let(:super_admin) { create(:user, type: 'SuperAdmin') }

  before do
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_return(collector)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'retains the trigger snapshot, refreshes metrics while paused and never auto-releases' do
    expect(service.evaluate!).to include(blocked: true)
    snapshot = EmailReputationState.find_by!(account_id: account.id).trigger_snapshot
    allow(collector).to receive(:call).and_return(metrics.merge(sent: 1000, permanent: 1))
    current = service.evaluate!
    expect(current).to include(blocked: true, resume_allowed: true)
    expect(current[:current_metrics]['sent']).to eq(1000)
    expect(current[:trigger_snapshot]).to eq(snapshot)
    expect(EmailReputationAudit.where(account_id: account.id, action: 'paused').count).to eq(1)
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
  end

  it 'reads the persisted legacy flag instead of a stale account and preserves unrelated JSON keys on release' do
    account.update!(internal_attributes: { 'other' => 'retained' })
    stale = Account.find(account.id)
    account.update!(internal_attributes: account.internal_attributes.merge('email_campaigns_paused' => { 'reason' => 'legacy' }))
    expect(EmailCampaigns::Guardrail.paused?(stale)).to be(true)
    allow(collector).to receive(:call).and_return(metrics.merge(permanent: 0, bounced: 0))
    result = service.resume!
    expect(result).to include(blocked: false, resume_allowed: true)
    expect(account.reload.internal_attributes).to eq('other' => 'retained')
    expect(result[:trigger_snapshot]['code']).to eq('legacy_pause')
  end

  it 'keeps legacy and structured protection enforced in shadow and warning modes' do
    service.evaluate!
    allow(collector).to receive(:call).and_return(metrics.merge(sent: 0, permanent: 0, bounced: 0))
    %w[shadow warning].each do |mode|
      evaluator = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode))
      expect(evaluator.evaluate!).to include(blocked: true, resume_allowed: false)
    end
    expect(EmailCampaigns::Guardrail.paused?(account)).to be(true)
  end

  it 'denies unsafe release without erasing the snapshot' do
    service.evaluate!
    expect(service.resume!).to include(blocked: true, resume_allowed: false)
    expect(EmailReputationAudit.where(action: 'released', account_id: account.id)).to be_empty
  end

  it 'requires an actual persisted SuperAdmin and bounded explicit exception' do
    admin = create(:user, account: account, role: :administrator)
    expect { service.override!(actor: admin, reason: 'Reviewed list source', duration_seconds: 60, message_budget: 1) }
      .to(raise_error { |error| expect(error.class.name).to eq('Pundit::NotAuthorizedError') })
    [[3601, 1], [60, 51], [0, 1], [60, 0]].each do |duration, budget|
      expect { service.override!(actor: super_admin, reason: 'Reviewed list source', duration_seconds: duration, message_budget: budget) }
        .to raise_error(ArgumentError)
    end
  end

  it 'audits overrides, revokes them for new harmful feedback, and retains protection and legacy mirror' do
    service.override!(actor: super_admin, reason: 'Reviewed list source', duration_seconds: 60, message_budget: 2)
    state = EmailReputationState.find_by!(account_id: account.id)
    expect(state.override_active?).to be(true)
    expect(EmailCampaigns::Guardrail.paused?(account)).to be(false)
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
    allow(collector).to receive(:harmful_feedback_fingerprint).and_return('new')
    expect(service.evaluate!).to include(override_active: false, blocked: true)
    expect(state.reload.override['revocation_reason']).to eq('new_harmful_feedback')
    audit = EmailReputationAudit.find_by!(account_id: account.id, action: 'override_granted')
    expect(audit.actor_id).to eq(super_admin.id)
    expect { audit.update!(action: 'modified') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'expires overrides without requiring a sweep or a new event' do
    service.override!(actor: super_admin, reason: 'Reviewed list source', duration_seconds: 1, message_budget: 2)
    travel 2.seconds do
      expect(EmailCampaigns::Guardrail.paused?(account)).to be(true)
    end
  end

  it 'does not let an override bypass a provider block' do
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(kind: 'provider', code: 'provider_blocked')
    result = service.override!(actor: super_admin, reason: 'Reviewed list source', duration_seconds: 60, message_budget: 2)
    expect(result).to include(resume_allowed: false, override_active: false)
    expect(result[:protection][:kind]).to eq('provider')
  end

  it 'protects the first snapshot and append-only audit against bulk SQL updates' do
    service.evaluate!
    state = EmailReputationState.find_by!(account_id: account.id)
    expect do
      EmailReputationState.transaction(requires_new: true) do
        # rubocop:disable Rails/SkipsModelValidations -- exercise the database invariant directly
        EmailReputationState.where(id: state.id).update_all(trigger_snapshot: {})
        # rubocop:enable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
    expect do
      EmailReputationAudit.transaction(requires_new: true) do
        EmailReputationAudit.where(account: account).delete_all
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it 'emits durable alerts in warning mode without enforcing the new pause threshold' do
    allow(collector).to receive(:call).and_return(sent: 1, permanent: 0, bounced: 0, complaints: 1)
    warning = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'warning'))
    expect(warning.evaluate!).to include(blocked: false, level: 'paused')
    expect(EmailReputationAudit.where(account: account, action: 'risk_alert').count).to eq(1)
    warning.evaluate!
    expect(EmailReputationAudit.where(account: account, action: 'risk_alert').count).to eq(1)
  end

  %w[shadow warning].each do |mode|
    it "denies normal resume while the legacy transient threshold remains active in #{mode}" do
      allow(collector).to receive(:call).and_return(metrics.merge(permanent: 0, bounced: 6, transient: 6))
      evaluator = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode))
      expect(evaluator.evaluate!).to include(blocked: true, resume_allowed: false)
      expect(evaluator.resume!).to include(blocked: true, resume_allowed: false)
      expect(evaluator.evaluate!).to include(blocked: true, resume_allowed: false)
      expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
      evaluator.override!(actor: super_admin, reason: 'Reviewed list source', duration_seconds: 60, message_budget: 2)
      expect(evaluator.resume!).to include(blocked: true, override_active: true, resume_allowed: true)
    end
  end

  it 'starts a new immutable incident after release and retains the first incident in the audit' do
    first = service.evaluate![:trigger_snapshot]
    allow(collector).to receive(:call).and_return(metrics.merge(permanent: 0, bounced: 0))
    expect(service.resume!).to include(blocked: false)
    expect(EmailReputationState.find_by!(account: account).trigger_snapshot).to eq(first)
    travel 1.hour do
      allow(collector).to receive(:call).and_return(metrics.merge(permanent: 9, bounced: 9))
      second = service.evaluate![:trigger_snapshot]
      expect(second['triggered_at']).not_to eq(first['triggered_at'])
      expect(second.dig('metrics', 'permanent')).to eq(9)
      expect(EmailReputationAudit.where(account: account, action: 'paused').order(:id).pluck(:snapshot)).to eq([first, second])
      expect(Time.iso8601(account.reload.internal_attributes.dig('email_campaigns_paused', 'at'))).to eq(Time.iso8601(second['triggered_at']))
    end
  end

  it 'imports the original legacy timestamp without inventing initial metrics' do
    original = 2.days.ago.change(usec: 0).iso8601
    account.update!(internal_attributes: { email_campaigns_paused: { at: original, reason: 'legacy' } })
    snapshot = service.evaluate![:trigger_snapshot]
    expect(snapshot).to include('triggered_at' => original, 'metrics' => nil, 'policy' => nil, 'code' => 'legacy_pause')
    expect(EmailReputationState.find_by!(account: account).triggered_at).to eq(Time.iso8601(original))
  end

  it 'safely uses observation time for malformed or future legacy timestamps' do
    [nil, 'invalid', 1.day.from_now.iso8601, 123].each do |value|
      snapshot = EmailCampaigns::Reputation::Snapshot.capture(EmailReputationState.new, { 'at' => value })
      expect(Time.iso8601(snapshot[:triggered_at])).to be_within(1.second).of(Time.current)
      expect(snapshot[:metrics]).to be_nil
    end
  end

  it 'publishes the generation of the evaluated observation without changing the original trigger' do
    service.evaluate!
    state = EmailReputationState.find_by!(account: account)
    initial = state.trigger_snapshot.deep_dup
    first_generation = state.current_metrics.fetch('evaluation_generation')
    expect(first_generation).to eq(state.observation_generation)
    service.evaluate!
    state.reload
    expect(state.current_metrics.fetch('evaluation_generation')).to eq(state.observation_generation)
    expect(state.observation_generation).to be > first_generation
    expect(state.trigger_snapshot).to eq(initial)
  end

  it 'cannot release or override an existing block with a safe observation superseded by feedback' do
    service.evaluate!
    state = EmailReputationState.find_by!(account: account)
    protected_attributes = state.attributes.slice('trigger_snapshot', 'triggered_at', 'current_metrics', 'evaluated_feedback_version', 'override')
    allow(collector).to receive(:call) do
      EmailCampaigns::Reputation::EvaluationQueue.invalidate(account.id)
      metrics.merge(permanent: 0, bounced: 0)
    end
    expect(service.resume!).to include(blocked: true, resume_allowed: false,
                                       protection: include(code: 'reputation_evaluation_superseded'))
    result = service.override!(actor: super_admin, reason: 'Reviewed synthetic source', duration_seconds: 60, message_budget: 2)
    expect(result).to include(blocked: true, resume_allowed: false, override_active: false)
    expect(state.reload.attributes.slice(*protected_attributes.keys)).to eq(protected_attributes)
    expect(state.feedback_version).to eq(2)
    expect(EmailReputationAudit.where(account: account, action: %w[released override_granted])).to be_empty
  end

  %w[shadow warning].each do |mode|
    it "adds legacy protection from a superseded harmful observation in #{mode} without publishing stale metrics" do
      legacy_harmful = metrics.merge(sent: 50, permanent: 0, bounced: 3, transient: 3)
      allow(collector).to receive(:call) do
        EmailCampaigns::Reputation::EvaluationQueue.invalidate(account.id)
        legacy_harmful
      end
      evaluator = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode))
      result = evaluator.evaluate!
      expect(result).to include(blocked: true, resume_allowed: false, current_metrics: {})
      persisted = EmailReputationState.find_by!(account: account).trigger_snapshot
      expect(persisted['superseded']).to be(true)
      expect(result.dig(:trigger_snapshot, 'metrics', 'sent')).to eq(50)
      expect(result.dig(:trigger_snapshot, 'metrics', 'pause')).to be(true)
      expect(result.dig(:trigger_snapshot, 'metrics', 'policy_pause')).to be(false)
      expect(result.dig(:trigger_snapshot, 'metrics', 'effective_pause')).to be(true)
      expect(EmailReputationAudit.where(account: account, action: 'paused').count).to eq(1)
    end
  end
end
