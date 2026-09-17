require 'rails_helper'

RSpec.describe EmailCampaigns::Presentation::Protection do
  subject(:dto) { presenter.call(campaign: campaign, preflight: preflight) }

  let(:now) { Time.zone.parse('2026-09-16 12:00:00 UTC') }
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:email_campaign, account: account, status: :paused, pause_reason: { kind: 'manual', code: 'manual_pause' }) }
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:provider_config) do
    instance_double(EmailCampaigns::Reputation::ProviderConfig, enabled: false, manual_block: false,
                                                                provider_key: 'ses:synthetic:region', max_age: 900, unknown_action: 'block')
  end
  let(:metrics) do
    counts = { sent: 200, permanent: 1, transient: 2, unknown: 3, complaints: 0, bounced: 6 }
    counts.merge(policy.evaluate(counts)).merge(evaluation_generation: 4,
                                                cohort_start: (now - 7.days).iso8601, cohort_end: now.iso8601).deep_stringify_keys
  end
  let(:state) do
    EmailReputationState.create!(account: account, current_metrics: metrics, policy: policy.snapshot,
                                 level: 'healthy', evaluated_at: now, observation_generation: 4,
                                 feedback_version: 2, evaluated_feedback_version: 2)
  end
  let(:presenter) { described_class.new(account: account, actor: actor, now: now) }
  let(:hygiene_mode) { 'enforce' }
  let(:hygiene_config) { EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => hygiene_mode) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                      preflight_checked_at: now, preflight_valid_until: now + 1.hour)
  end
  let(:preflight) { EmailCampaigns::Presentation::Hygiene.new(campaign).call }

  around { |example| travel_to(now) { example.run } }

  before do
    allow(EmailCampaigns::HygieneConfig).to receive(:new).and_return(hygiene_config)
    allow(EmailCampaigns::Reputation::Policy).to receive(:new).and_return(policy)
    allow(EmailCampaigns::Reputation::ProviderConfig).to receive(:new).and_return(provider_config)
  end

  it 'returns the exact public keys and null no-data without collecting, creating state or invoking the evaluator', :aggregate_failures do
    expect(EmailCampaigns::Reputation::Metrics).not_to receive(:new)
    expect(EmailCampaigns::Reputation::Evaluator).not_to receive(:new)
    expect(EmailCampaigns::Reputation::ProviderMonitor).not_to receive(:new)
    expect(EmailCampaigns::AddressPreflight).not_to receive(:new)
    expect(EmailCampaigns::DomainValidator).not_to receive(:new)
    result = dto
    expect(result.keys).to contain_exactly(:state, :reason_code, :mode, :scope, :current, :trigger, :provider,
                                           :capabilities, :domains, :release_eligible)
    expect(result).to include(state: 'unknown', scope: 'account', trigger: nil, domains: [], release_eligible: false)
    expect(result[:current]).to eq(sent: nil, permanent_bounces: nil, temporary_bounces: nil, unknown_bounces: nil,
                                   complaints: nil, hard_bounce_rate: nil, complaint_rate: nil,
                                   evaluated_at: nil, window_start: nil, window_end: nil)
    expect(EmailReputationState.where(account: account)).not_to exist
  end

  it 'normalizes actual persisted campaign reason objects without forwarding free text' do
    {
      'manual_pause' => 'manual', 'reputation_paused' => 'reputation', 'legacy_pause' => 'reputation',
      'provider_manual_block' => 'provider_blocked', 'provider_telemetry_unknown' => 'provider_blocked',
      'hygiene_validation_required' => 'preflight_review', 'private operator reason' => 'unknown'
    }.each do |code, expected|
      campaign.pause_reason = { 'kind' => 'ignored', 'code' => code, 'reason' => 'never expose' }
      expect(described_class.pause_reason(campaign)).to eq(expected)
    end
  end

  it 'preserves manual campaign pause separately and expresses internal ratios only as public percentages' do
    state
    expect(described_class.pause_reason(campaign)).to eq('manual')
    expect(dto).to include(state: 'healthy', reason_code: nil, release_eligible: true)
    expect(dto[:current]).to eq(sent: 200, permanent_bounces: 1, temporary_bounces: 2, unknown_bounces: 3, complaints: 0,
                                hard_bounce_rate: 0.5, complaint_rate: 0.0, evaluated_at: now,
                                window_start: (now - 7.days).iso8601, window_end: now.iso8601)
    expect(dto[:capabilities]).to eq(reevaluate: true, resume: true, override: false)
    expect(state.reload.current_metrics['permanent_ratio']).to eq(0.005)
    expect(campaign.reload).to be_paused
  end

  it 'maps both fractional rates to numeric percentages without changing stored ratios' do
    state.update!(current_metrics: metrics.merge('permanent_ratio' => 0.025, 'complaint_ratio' => 0.001))
    expect(dto[:current]).to include(hard_bounce_rate: 2.5, complaint_rate: 0.1)
    expect(state.reload.current_metrics).to include('permanent_ratio' => 0.025, 'complaint_ratio' => 0.001)
  end

  it 'keeps an eligible sticky pause latched and its trigger immutable, separately from live telemetry' do
    trigger = { triggered_at: (now - 1.day).iso8601, code: 'reputation_threshold',
                metrics: metrics.merge('sent' => 100, 'permanent' => 10, 'permanent_ratio' => 0.1),
                actor_id: 123, reason: 'private operator reason' }
    state.update!(blocked: true, triggered_at: now - 1.day, trigger_snapshot: trigger)
    before_read = state.reload.attributes
    expect(dto).to include(state: 'paused', reason_code: 'reputation', release_eligible: true)
    expect(dto[:capabilities][:resume]).to be(true)
    expect(dto[:trigger]).to include(at: (now - 1.day).iso8601, reason_code: 'reputation')
    expect(dto[:trigger][:metrics]).to include(sent: 100, permanent_bounces: 10, hard_bounce_rate: 10.0)
    expect(dto[:current]).to include(sent: 200, permanent_bounces: 1, hard_bounce_rate: 0.5)
    expect(dto.to_json).not_to include('private operator reason', 'actor_id')
    expect(state.reload.attributes).to eq(before_read)
  end

  it 'does not equate an aged-out cohort to remediation or clear a sticky pause' do
    state.update!(blocked: true, current_metrics: metrics.merge('sent' => 0, 'permanent_ratio' => nil, 'complaint_ratio' => nil))
    expect(dto).to include(state: 'paused', release_eligible: false)
    expect(dto[:current]).to include(sent: 0, hard_bounce_rate: nil, complaint_rate: nil)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'allows an unblocked manual pause without claiming an empty SES sample is healthy' do
    state.update!(current_metrics: metrics.merge('sent' => 0, 'permanent_ratio' => nil, 'complaint_ratio' => nil))
    expect(dto).to include(state: 'unknown', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(true)
  end

  it 'allows a manual pause below the SES minimum sample without demanding a generation marker' do
    state.update!(current_metrics: metrics.merge('sent' => 20).except('evaluation_generation'))
    expect(dto[:release_eligible]).to be(false)
    expect(dto[:capabilities][:resume]).to be(true)
  end

  it 'rejects passing stored flags if actual metrics fail the real resume policy' do
    state.update!(blocked: true, current_metrics: metrics.merge('complaints' => 1))
    expect(dto).to include(state: 'paused', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  [nil, 0, 3, '4'].each do |generation|
    it "fails closed with missing or stale published generation #{generation.inspect}" do
      state.update!(blocked: true, current_metrics: metrics.merge('evaluation_generation' => generation))
      expect(dto[:release_eligible]).to be(false)
      expect(dto[:capabilities][:resume]).to be(false)
    end
  end

  it 'rejects feedback received after the published evaluation' do
    state.update!(blocked: true, feedback_version: 3)
    expect(dto[:release_eligible]).to be(false)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'rejects an expired evaluation even if no new observation has started' do
    state.update!(blocked: true, evaluated_at: now - 8.days)
    expect(dto[:release_eligible]).to be(false)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'does not grant resume on an unknown evaluated level' do
    state.update!(blocked: true, level: 'unknown')
    expect(dto).to include(state: 'paused', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'requires the evaluated policy to match the current policy' do
    state.update!(policy: state.policy.merge('mode' => 'shadow'))
    expect(dto[:release_eligible]).to be(false)
  end

  it 'does not let an active override substitute for passing metrics or a current generation' do
    state.update!(blocked: true, current_metrics: metrics.except('evaluation_generation'),
                  override: { expires_at: (now + 1.hour).iso8601, remaining: 10, reason: 'private reason', actor_id: actor.id })
    expect(dto).to include(state: 'paused', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(false)
    expect(dto.to_json).not_to include('remaining', 'expires_at', 'actor_id', 'private reason')
  end

  it 'maps warning into attention and rejects unexpected persisted levels loudly' do
    state.update!(level: 'warning')
    expect(dto[:state]).to eq('attention')
    allow(EmailReputationState).to receive(:find_by).with(account_id: account.id).and_return(state)
    state.level = 'future_level'
    expect { described_class.new(account: account, now: now).call }.to raise_error(KeyError)
  end

  [nil, {}, { total: 2, ready: 1 }, { total: 1, ready: 1, protected: 0, invalid: 0, review: 0, unknown: 1, unchecked: 0 }].each do |counts|
    it "denies resume with missing or inconsistent hygiene #{counts.inspect}" do
      state
      result = presenter.call(campaign: campaign, preflight: counts && { mode: 'enforce', counts: counts })
      expect(result[:release_eligible]).to be(true)
      expect(result[:capabilities][:resume]).to be(false)
    end
  end

  unvalidated_statuses = %w[invalid review unknown unchecked].freeze
  %w[shadow warning].each do |mode|
    context "with #{mode} hygiene" do
      let(:hygiene_mode) { mode }
      let(:policy) { EmailCampaigns::Reputation::Policy.new({}) }

      unvalidated_statuses.each do |classification|
        it "allows an unblocked manual pause with #{classification}, zero sends and no risk state" do
          recipient.update!(preflight_status: classification, preflight_checked_at: nil, preflight_valid_until: nil)
          expect(hygiene_config.dns_enabled?).to be(false)
          expect(dto).to include(state: 'unknown', release_eligible: false)
          expect(dto[:provider]).to eq(state: 'unknown', observed_at: nil)
          expect(dto[:capabilities][:resume]).to be(true)
          expect(EmailReputationState.where(account: account)).not_to exist
        end
      end

      it 'still denies an active import' do
        campaign.email_campaign_imports.create!(status: :queued)
        expect(dto[:capabilities][:resume]).to be(false)
      end

      it 'still denies a protected tenant without fresh release evidence' do
        state.update!(blocked: true, current_metrics: metrics.except('evaluation_generation'))
        expect(dto).to include(state: 'paused', release_eligible: false)
        expect(dto[:capabilities][:resume]).to be(false)
      end
    end
  end

  %w[unchecked invalid review unknown].each do |classification|
    it "denies unvalidated #{classification} recipients in enforce even for an unblocked manual pause" do
      recipient.update!(preflight_status: classification, preflight_checked_at: nil, preflight_valid_until: nil)
      expect(dto[:capabilities][:resume]).to be(false)
    end
  end

  it 'requires all pending preflight decisions to pass in enforce, not just one valid row' do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'unchecked')
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'uses the configured mode instead of accepting a permissive mismatched DTO' do
    expect(presenter.call(campaign: campaign, preflight: preflight.merge(mode: 'shadow'))[:capabilities][:resume]).to be(false)
  end

  [nil, [], 'ready'].each do |malformed|
    it "denies malformed preflight #{malformed.inspect}" do
      expect(presenter.call(campaign: campaign, preflight: malformed)[:capabilities][:resume]).to be(false)
    end
  end

  it 'does not replace missing validation timestamps or expired validation with a ready count' do
    reported = preflight
    recipient.update!(preflight_checked_at: nil)
    expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
    recipient.update!(preflight_checked_at: now - 1.hour, preflight_valid_until: now)
    expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
  end

  ineligible_statuses = %i[suppressed unsubscribed complained sent failed delivered].freeze
  %w[shadow warning enforce].each do |mode|
    context "with real recipient eligibility in #{mode}" do
      let(:hygiene_mode) { mode }

      it 'denies an empty campaign even with stale ready counts' do
        reported = preflight
        recipient.destroy!
        expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
        expect(dto[:capabilities][:resume]).to be(false)
      end

      it 'denies a campaign whose only row has a legacy suppression' do
        reported = preflight
        EmailSuppression.create!(account: account, email: recipient.email, reason: 'unsubscribe')
        expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
        expect(dto[:capabilities][:resume]).to be(false)
      end

      it 'denies active suppression state without loading the suppression list' do
        reported = preflight
        EmailSuppressionState.create!(account: account, email: recipient.email, reason: 'complaint', active: true)
        expect(EmailSuppression).not_to receive(:suppressed_set_for)
        expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
      end

      it 'allows an eligible pending row alongside a protected row without changing either' do
        protected = create(:email_campaign_recipient, email_campaign: campaign, status: :suppressed)
        expect(dto[:capabilities][:resume]).to be(true)
        expect(protected.reload).to be_suppressed
        expect(recipient.reload).to be_pending
      end

      ineligible_statuses.each do |status|
        it "does not offer resume for an exclusively #{status} campaign" do
          recipient.update!(status: status)
          expect(dto[:capabilities][:resume]).to be(false)
        end
      end

      [{ sent_at: Time.zone.parse('2026-09-16 11:00:00 UTC') }, { ses_message_id: 'synthetic-accepted' }].each do |evidence|
        it "denies an ambiguous pending row carrying #{evidence.keys.first}" do
          reported = preflight
          recipient.update!(evidence)
          expect(presenter.call(campaign: campaign, preflight: reported)[:capabilities][:resume]).to be(false)
        end
      end
    end
  end

  it 'denies resume while an import is active, with otherwise ready hygiene' do
    state
    campaign.email_campaign_imports.create!(status: :queued)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'does not advertise release controls for an agent or an account without a selected campaign' do
    state
    agent = create(:user, account: account, role: :agent)
    result = described_class.new(account: account, actor: agent, now: now).call(campaign: campaign, preflight: preflight)
    expect(result[:capabilities]).to eq(reevaluate: false, resume: false, override: false)
    expect(presenter.call[:capabilities]).to eq(reevaluate: false, resume: false, override: false)
  end

  it 'does not grant tenant capabilities to an administrator of a different tenant' do
    state
    foreign_admin = create(:user, account: create(:account), role: :administrator)
    result = described_class.new(account: account, actor: foreign_admin, now: now).call(campaign: campaign, preflight: preflight)
    expect(result[:capabilities]).to eq(reevaluate: false, resume: false, override: false)
    expect { presenter.call(campaign: create(:email_campaign)) }.to raise_error(ArgumentError, 'campaign account mismatch')
  end

  it 'honors campaign policy denial even for a tenant administrator' do
    state
    denied = instance_double(EmailCampaignPolicy, update?: false)
    allow(EmailCampaignPolicy).to receive(:new).and_return(denied)
    expect(dto[:capabilities]).to eq(reevaluate: false, resume: false, override: false)
  end

  it 'keeps the database SuperAdmin distinction separate from administrator membership' do
    state
    expect(dto[:capabilities][:override]).to be(false)
    actor.update!(type: 'SuperAdmin')
    elevated = described_class.new(account: account, actor: actor.reload, now: now).call(campaign: campaign, preflight: preflight)
    expect(elevated[:capabilities][:override]).to be(true)
  end

  it 'never uses another tenant state, domain or private policy fields' do
    foreign = create(:account)
    EmailReputationState.create!(account: foreign, blocked: true, level: 'paused',
                                 current_metrics: metrics.merge('domains' => ['private.example.org']))
    expect(dto).to include(state: 'unknown', release_eligible: false, domains: [])
    expect(dto.to_json).not_to include('private.example.org', 'evaluation_generation', 'feedback_version', 'thresholds')
  end

  it 'invalidates release after a harmful event advances feedback and observation generations' do
    state.update!(blocked: true)
    expect(dto[:capabilities][:resume]).to be(true)
    state.update!(feedback_version: 3, observation_generation: 5)
    fresh = described_class.new(account: account, actor: actor, now: now).call(campaign: campaign, preflight: preflight)
    expect(fresh).to include(state: 'paused', release_eligible: false)
    expect(fresh[:capabilities][:resume]).to be(false)
  end

  it 'retains legacy account protection without inventing release evidence' do
    account.update!(internal_attributes: { 'email_campaigns_paused' => true })
    expect(dto).to include(state: 'paused', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'requires the resume policy even when the update policy allows the actor' do
    allow(EmailCampaignPolicy).to receive(:new).and_return(instance_double(EmailCampaignPolicy, update?: true, reevaluate?: true, resume?: false))
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'does not offer resume when the campaign is already sending' do
    campaign.update!(status: :sending)
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'allows manual direct inbox without any SES sample or provider gate' do
    inbox = create(:inbox, :with_email, account: account)
    campaign.update!(delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    allow(provider_config).to receive(:manual_block).and_return(true)
    expect(EmailCampaigns::Reputation::ProviderGate).not_to receive(:protection)
    expect(dto[:provider]).to eq(state: 'not_applicable', observed_at: nil)
    expect(dto).to include(state: 'unknown', release_eligible: false)
    expect(dto[:capabilities][:resume]).to be(true)
  end

  context 'with provider monitoring' do
    before { allow(provider_config).to receive(:enabled).and_return(true) }

    it 'maps missing monitoring to blocked through the real fail-closed provider gate' do
      state
      expect(dto[:provider]).to eq(state: 'blocked', observed_at: nil)
      expect(dto).to include(reason_code: 'provider_blocked', release_eligible: false)
      expect(dto[:capabilities][:resume]).to be(false)
    end

    it 'keeps allowed unknown monitoring visibly unknown instead of healthy' do
      state
      allow(provider_config).to receive(:unknown_action).and_return('allow')
      expect(dto[:provider]).to eq(state: 'unknown', observed_at: nil)
      expect(dto[:release_eligible]).to be(true)
    end

    it 'shows healthy only with fresh persisted provider monitoring' do
      state
      EmailProviderState.create!(provider_key: provider_config.provider_key, status: 'healthy', observed_at: now)
      expect(dto[:provider]).to eq(state: 'healthy', observed_at: now)
      expect(dto[:release_eligible]).to be(true)
    end

    it 'does not mistake stale provider telemetry for healthy' do
      state
      EmailProviderState.create!(provider_key: provider_config.provider_key, status: 'healthy', observed_at: now - 901.seconds)
      expect(dto[:provider]).to eq(state: 'blocked', observed_at: now - 901.seconds)
      expect(dto[:release_eligible]).to be(false)
    end

    it 'retains the provider latch even when current telemetry is healthy and strips provider private fields' do
      state
      EmailProviderState.create!(provider_key: provider_config.provider_key, status: 'healthy', observed_at: now,
                                 blocked: true, manual_reason: 'private operator reason', telemetry: { other_tenant: 'private.example.org' })
      expect(dto[:provider]).to eq(state: 'blocked', observed_at: now)
      expect(dto[:release_eligible]).to be(false)
      expect(dto.to_json).not_to include('ses:synthetic', 'private operator reason', 'private.example.org', 'other_tenant')
    end

    it 'excludes SES provider gates for direct inbox but retains tenant protection and its SES metric scope' do
      state.update!(blocked: true, current_metrics: metrics.merge('resume_allowed' => false))
      inbox = create(:inbox, :with_email, account: account)
      direct = create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_identity: nil,
                                       sender_inbox: inbox, status: :paused)
      expect(EmailCampaigns::Reputation::ProviderGate).not_to receive(:protection)
      result = presenter.call(campaign: direct, preflight: preflight)
      expect(result).to include(state: 'paused', reason_code: 'reputation', release_eligible: false)
      expect(result[:provider]).to eq(state: 'not_applicable', observed_at: nil)
      expect(result[:current][:sent]).to eq(200)
      expect(result[:capabilities][:resume]).to be(false)
    end
  end

  it 'bounds reputation reads across repeated presentations and never writes during a read' do
    state
    campaign
    actor
    preflight
    queries = []
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      queries << payload[:sql] unless payload[:name] == 'SCHEMA'
    end
    begin
      3.times { presenter.call(campaign: campaign, preflight: preflight) }
      expect(queries.grep(/\ASELECT.*"email_reputation_states"/i).size).to eq(1)
      expect(queries.grep(/\ASELECT.*"email_provider_states"/i).size).to eq(1)
      expect(queries.grep(/\ASELECT 1 AS one FROM "email_campaign_recipients"/i).size).to eq(6)
      expect(queries.grep(/\A(?:INSERT|UPDATE|DELETE)/i)).to be_empty
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  it 'does not call disabled monitoring healthy even with an old healthy row' do
    state
    EmailProviderState.create!(provider_key: provider_config.provider_key, status: 'healthy', observed_at: now)
    expect(dto[:provider]).to eq(state: 'unknown', observed_at: nil)
    expect(dto[:release_eligible]).to be(true)
  end

  it 'respects an explicit provider block even when monitoring is disabled' do
    state
    allow(provider_config).to receive(:manual_block).and_return(true)
    expect(dto[:provider]).to eq(state: 'blocked', observed_at: nil)
    expect(dto[:release_eligible]).to be(false)
    expect(dto[:state]).to eq('healthy')
    expect(dto[:capabilities][:resume]).to be(false)
  end

  it 'retains a sticky provider block with monitoring disabled and a healthy manual account' do
    state
    EmailProviderState.create!(provider_key: provider_config.provider_key, status: 'healthy', observed_at: now, blocked: true)
    expect(dto[:provider][:state]).to eq('blocked')
    expect(dto[:state]).to eq('healthy')
    expect(dto[:capabilities][:resume]).to be(false)
  end
end
