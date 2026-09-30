require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Evaluator do
  let(:account) { create(:account) }
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:service) { described_class.new(account, policy: policy) }
  let(:metrics) { { sent: 100, permanent: 5, bounced: 5, complaints: 0, transient: 0 } }
  let(:collector) { instance_double(EmailCampaigns::Reputation::Metrics, call: metrics, harmful_feedback_fingerprint: 'original') }

  before do
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_return(collector)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'publishes high risk as a diagnostic without creating an account block or pause history' do
    expect(service.evaluate!).to include(blocked: false, level: 'high_risk', resume_allowed: true)
    state = EmailReputationState.find_by!(account: account)
    expect(state.current_metrics['permanent']).to eq(5)
    expect(state.blocked).to be(false)
    expect(state.trigger_snapshot).to eq({})
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_nil
    expect(EmailReputationAudit.where(account: account, action: 'paused')).to be_empty
    expect(EmailReputationAudit.where(account: account, action: 'risk_alert').count).to eq(1)
  end

  it 'preserves rollback flags, historical incidents, exceptions and unrelated account data on resume' do
    account.update!(internal_attributes: { other: 'retained', email_campaigns_paused: { reason: 'legacy' } })
    state = EmailReputationState.create!(account: account, blocked: true, trigger_snapshot: { code: 'legacy_pause' },
                                         override: { remaining: 2, expires_at: 1.hour.from_now.iso8601 })
    historical = state.attributes.slice('blocked', 'trigger_snapshot', 'override')
    expect(service.resume!).to include(blocked: false, override_active: false, resume_allowed: true)
    expect(state.reload.attributes.slice(*historical.keys)).to eq(historical)
    expect(account.reload.internal_attributes).to include('other' => 'retained', 'email_campaigns_paused' => be_present)
    expect(EmailCampaigns::Guardrail.paused?(account)).to be(false)
    expect(EmailReputationAudit.where(account: account, action: %w[released override_granted])).to be_empty
  end

  %w[shadow warning enforce].each do |mode|
    it "does not use local ratios or volume as sending authority in #{mode}" do
      allow(collector).to receive(:call).and_return(sent: 0, permanent: 0, bounced: 0, complaints: 1)
      evaluator = described_class.new(account, policy: EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode))
      expect(evaluator.evaluate!).to include(blocked: false, resume_allowed: true)
      expect { |block| evaluator.resume!(&block) }.to yield_control
    end
  end

  it 'requires a persisted SuperAdmin but retires account exceptions even for the operator' do
    admin = create(:user, account: account, role: :administrator)
    expect { service.override!(actor: admin) }.to(raise_error { |error| expect(error.class.name).to eq('Pundit::NotAuthorizedError') })
    operator = create(:user, type: 'SuperAdmin')
    expect { service.override!(actor: operator) }.to raise_error do |error|
      expect(error.class.name).to eq('CustomExceptions::EmailReputationOverride')
      expect(error.message).to eq('account_override_not_required')
    end
    expect(EmailReputationAudit.where(account: account, action: 'override_granted')).to be_empty
  end

  it 'denies resume on a global provider block, including an account with no sends' do
    allow(collector).to receive(:call).and_return(sent: 0, permanent: 0, bounced: 0, complaints: 0)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(kind: 'provider', code: 'provider_blocked')
    called = false
    result = service.resume! { called = true }
    expect(result).to include(blocked: false, resume_allowed: false, protection: include(kind: 'provider'))
    expect(called).to be(false)
  end

  it 'does not apply SES protection to the direct inbox transport' do
    expect(EmailCampaigns::Reputation::ProviderGate).not_to receive(:protection)
    expect(service.resume!(delivery_mode: 'direct_inbox')).to include(resume_allowed: true)
  end

  it 'retains the database protection for historical snapshots and append-only audits' do
    state = EmailReputationState.create!(account: account, blocked: true, triggered_at: 1.hour.ago, trigger_snapshot: { code: 'legacy_pause' })
    service.evaluate!
    expect do
      EmailReputationState.transaction(requires_new: true) do
        # rubocop:disable Rails/SkipsModelValidations -- exercise the database invariant directly
        EmailReputationState.where(id: state.id).update_all(trigger_snapshot: {})
        # rubocop:enable Rails/SkipsModelValidations
      end
    end.to(raise_error { |error| expect(error.message).to include('snapshot is immutable') })
    expect do
      EmailReputationAudit.transaction(requires_new: true) do
        EmailReputationAudit.where(account: account).delete_all
      end
    end.to(raise_error { |error| expect(error.message).to include('append-only') })
  end

  it 'does not duplicate alerts for an unchanged observation' do
    service.evaluate!
    service.evaluate!
    expect(EmailReputationAudit.where(account: account, action: 'risk_alert').count).to eq(1)
  end

  it 'publishes the current observation generation' do
    service.evaluate!
    state = EmailReputationState.find_by!(account: account)
    first_generation = state.current_metrics.fetch('evaluation_generation')
    service.evaluate!
    expect(state.reload.current_metrics.fetch('evaluation_generation')).to eq(state.observation_generation)
    expect(state.observation_generation).to be > first_generation
  end

  it 'does not publish superseded diagnostics or let them override the global sending decision' do
    service.evaluate!
    state = EmailReputationState.find_by!(account: account)
    published = state.attributes.slice('current_metrics', 'evaluated_feedback_version')
    allow(collector).to receive(:call) do
      EmailCampaigns::Reputation::EvaluationQueue.invalidate(account.id)
      metrics.merge(permanent: 0, bounced: 0)
    end
    expect(service.resume!).to include(blocked: false, resume_allowed: true)
    expect(state.reload.attributes.slice(*published.keys)).to eq(published)
    expect(state.feedback_version).to eq(1)
  end
end
