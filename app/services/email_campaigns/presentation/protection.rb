# Tenant DTO only. Manual resume does not require reputational remediation;
# protected accounts still require fresh release evidence. GET never releases a latch.
class EmailCampaigns::Presentation::Protection
  LEVELS = { 'unknown' => 'unknown', 'healthy' => 'healthy', 'warning' => 'attention',
             'attention' => 'attention', 'high_risk' => 'high_risk', 'paused' => 'paused' }.freeze
  REASONS = {
    'manual' => 'manual', 'manual_pause' => 'manual', 'user' => 'manual',
    'reputation' => 'reputation', 'reputation_guardrail' => 'reputation',
    'hard_bounce_rate' => 'hard_bounce_rate', 'complaint_rate' => 'complaint_rate',
    'ses_account_paused' => 'provider_blocked', 'ses_sending_disabled' => 'provider_blocked',
    'reputation_paused' => 'reputation', 'reputation_threshold' => 'reputation', 'legacy_pause' => 'reputation',
    'permanent_failures' => 'hard_bounce_rate', 'complaints' => 'complaint_rate',
    'provider_manual_block' => 'provider_blocked', 'provider_blocked' => 'provider_blocked',
    'provider_telemetry_unknown' => 'provider_blocked', 'hygiene_validation_required' => 'preflight_review'
  }.freeze

  def self.pause_reason(campaign)
    reason = campaign.pause_reason
    code = reason.is_a?(Hash) ? reason['code'] : reason
    REASONS.fetch(code, code.nil? || code == '' || reason == {} ? nil : 'unknown')
  end

  def initialize(account:, actor: nil, now: Time.current)
    @account = account
    @actor = actor
    @now = now
    @state = EmailReputationState.find_by(account_id: account.id)
    @policy = EmailCampaigns::Reputation::Policy.new
    @provider = EmailCampaigns::Presentation::ProtectionProvider.new(now: now)
    @membership = account.account_users.find_by(user_id: actor.id) if actor
  end

  def call(campaign: nil, preflight: nil)
    raise ArgumentError, 'campaign account mismatch' if campaign && campaign.account_id != @account.id

    provider = @provider.call(direct: campaign&.direct_inbox? == true)
    eligible = release_eligible? && !provider[:blocked]
    {
      state: display_state, reason_code: reason_code(provider), mode: @policy.mode, scope: 'account',
      current: EmailCampaigns::Presentation::ProtectionMetrics.new(@state&.current_metrics, evaluated_at: @state&.evaluated_at).call,
      trigger: trigger, provider: provider.slice(:state, :observed_at), release_eligible: eligible,
      capabilities: capabilities(campaign, preflight, eligible, provider), domains: []
    }
  end

  private

  def display_state
    level = LEVELS.fetch(@state.level) if @state
    return 'paused' if blocked?
    return 'unknown' unless @state&.evaluated_at && @state.current_metrics['sent'].is_a?(Integer) && @state.current_metrics['sent'].positive?

    level
  end

  def blocked?
    @state&.blocked || @account.internal_attributes['email_campaigns_paused'].present?
  end

  def reason_code(provider)
    return 'provider_blocked' if provider[:blocked]
    return 'reputation' if blocked?

    reason = @state&.current_metrics&.fetch('reasons', [])&.first
    reason ? REASONS.fetch(reason, 'unknown') : nil
  end

  def trigger
    snapshot = @state&.trigger_snapshot
    return if snapshot.blank?

    { at: snapshot['triggered_at'], reason_code: REASONS.fetch(snapshot['code'], 'unknown'),
      metrics: EmailCampaigns::Presentation::ProtectionMetrics.new(snapshot['metrics']).call }
  end

  def release_eligible?
    return false unless current_evaluation?

    metrics = @state.current_metrics
    return false unless metrics['resume_allowed'] == true && @state.policy == @policy.snapshot.deep_stringify_keys

    # Evaluate the real pure policy; no duplicate thresholds or percentages in the decision path.
    decision = @policy.evaluate(metrics.symbolize_keys)
    return false unless decision.fetch(:resume_allowed)
    return true if @policy.mode == 'enforce'

    EmailCampaigns::Reputation::LegacyDecision.resume_allowed?(metrics.symbolize_keys, proposed: true)
  end

  def current_evaluation?
    return false unless @state&.evaluated_at&.between?(@now - EmailCampaigns::Reputation::Policy::WINDOW_SECONDS, @now)
    return false if @state.level == 'unknown'

    published_generation? && @state.evaluated_feedback_version == @state.feedback_version && complete_metrics?
  end

  def published_generation?
    generation = @state.current_metrics['evaluation_generation']
    # The evaluator publishes this marker with current_metrics inside its successful generation CAS.
    # Older rows cannot prove which observation produced them, and therefore cannot advertise release.
    generation.is_a?(Integer) && generation.positive? && generation == @state.observation_generation
  end

  def complete_metrics?
    metrics = @state.current_metrics
    %w[sent permanent transient unknown complaints bounced].all? { |key| metrics[key].is_a?(Integer) && metrics[key] >= 0 }
  end

  def capabilities(campaign, preflight, eligible, provider)
    denied = { reevaluate: false, resume: false, override: false }
    return denied unless @actor && campaign

    context = { user: @actor, account: @account, account_user: @membership }
    policy = EmailCampaignPolicy.new(context, campaign)
    return denied unless policy.update?

    {
      reevaluate: policy.reevaluate?,
      resume: policy.resume? && resumable?(campaign, preflight, eligible, provider),
      override: operator?
    }
  end

  def resumable?(campaign, preflight, eligible, provider)
    campaign.paused? && !provider[:blocked] && (!blocked? || eligible) && hygiene_ready?(campaign, preflight)
  end

  def operator?
    return @operator if defined?(@operator)

    @operator = SuperAdmin.exists?(id: @actor.id)
  end

  def hygiene_ready?(campaign, preflight)
    return false if campaign.recipient_import_active?

    config = EmailCampaigns::Presentation::Configuration.hygiene
    return false unless valid_preflight?(preflight, config)

    # Presentation counts include non-pending and ambiguous legacy rows. Prove an
    # actual candidate with bounded SQL, using the shared suppression predicates.
    state = EmailCampaigns::Reports::RecipientState.new(campaign, now: @now)
    return false unless enforce_ready?(campaign, config, state)

    recipients = state.resume_candidates
    recipients = recipients.where(id: state.ready_ids) if config.enforce?
    recipients.exists?
  end

  def valid_preflight?(preflight, config)
    return false unless preflight.is_a?(Hash) && preflight[:mode] == config.mode

    counts = preflight[:counts]
    return false unless complete_hygiene_counts?(counts)
    return false unless counts[:total] == counts.values_at(:ready, :protected, :invalid, :review, :unknown, :unchecked).sum
    return false unless counts[:total] > counts[:protected]

    !config.enforce? || counts[:ready].positive?
  end

  def enforce_ready?(campaign, config, state)
    return true unless config.enforce?
    return false if campaign.preflight_summary['rechecking']

    # Same unresolved scope as admission, subtracting the active protection union
    # in SQL instead of materializing batches during a GET.
    unresolved = EmailCampaigns::PreflightDecision.new(config: config).unresolved(campaign)
    !unresolved.where.not(id: state.protected_ids).exists?
  end

  def complete_hygiene_counts?(counts)
    counts.is_a?(Hash) && %i[total ready protected invalid review unknown unchecked].all? { |key| counts[key].is_a?(Integer) && counts[key] >= 0 }
  end
end
