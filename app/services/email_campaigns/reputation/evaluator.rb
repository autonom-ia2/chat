class EmailCampaigns::Reputation::Evaluator
  FLAG_KEY = 'email_campaigns_paused'.freeze

  def initialize(account, policy: EmailCampaigns::Reputation::Policy.new)
    @account_id = account.id
    @policy = policy
  end

  # Local reputation is diagnostic only. It publishes metrics/alerts and retires
  # historical tenant latches, but it never decides delivery admission.
  def evaluate!
    observed do |account, state, observation|
      refresh!(account, state, observation)
      payload(state)
    end
  end

  # Compatibility API retained for older internal callers.
  def resume!(delivery_mode: 'ses', **_options)
    result = evaluate!
    provider = EmailCampaigns::Reputation::ProviderGate.protection if delivery_mode.to_s == 'ses'
    return result.merge(resume_allowed: false, protection: provider) if provider

    yield if block_given?
    result.merge(blocked: false, override_active: false, resume_allowed: true)
  end

  def override!(actor:, **_options)
    raise Pundit::NotAuthorizedError unless actor && SuperAdmin.exists?(id: actor.id)

    # Tenant-level reputation no longer blocks delivery, so there is nothing to override.
    raise CustomExceptions::EmailReputationOverride, 'tenant reputation override retired'
  end

  private

  # Collection never holds Account/state locks. A later committed feedback event
  # invalidates this observation and requests another analytics pass.
  def observed
    observation = EmailCampaigns::Reputation::Observation.new(@account_id).collect
    account = Account.find(@account_id)
    account.with_lock do
      state = EmailReputationState.find_by!(account_id: @account_id)
      state.with_lock do
        unless observation.current?(state)
          request_follow_up
          next payload(state)
        end

        yield account, state, observation
      end
    end
  end

  def request_follow_up
    ActiveRecord.after_all_transactions_commit do
      EmailCampaigns::Reputation::EvaluationQueue.request(@account_id)
    end
  end

  def refresh!(account, state, observation)
    decision = @policy.evaluate(observation.metrics)
    retired = local_protection_present?(account, state)
    state.assign_attributes(state_attributes(observation, decision))
    record_alert!(state)
    state.save!
    retire_local_protection!(state) if retired
  end

  def state_attributes(observation, decision)
    {
      current_metrics: published_metrics(observation, decision).stringify_keys,
      policy: @policy.snapshot,
      evaluated_at: Time.current,
      level: diagnostic_level(decision[:level]),
      evaluated_feedback_version: observation.feedback_version,
      blocked: false,
      override: {}
    }
  end

  def published_metrics(observation, decision)
    observation.metrics.merge(decision).merge(
      policy_pause: decision[:pause],
      pause: false,
      resume_allowed: true,
      evaluation_generation: observation.generation
    )
  end

  def diagnostic_level(level)
    level == 'paused' ? 'high_risk' : level
  end

  def local_protection_present?(account, state)
    state.blocked || state.override.present? || account.internal_attributes[FLAG_KEY].present?
  end

  def retire_local_protection!(state)
    remove_legacy_flag!
    audit!(state, 'tenant_protection_retired')
    ActiveRecord.after_all_transactions_commit do
      EmailCampaigns::TenantProtectionRetirementJob.perform_later(@account_id)
    end
  end

  # Durable local alerts remain useful for diagnosis, but never become an admission gate.
  def record_alert!(state)
    return if @policy.mode == 'shadow'

    previous = state.current_metrics_in_database
    current = state.current_metrics
    risk_changed = state.will_save_change_to_level? && state.level != 'healthy'
    new_complaint = current.fetch('complaints') > previous.fetch('complaints', 0)
    audit!(state, 'risk_alert') if risk_changed || new_complaint
  end

  # Atomic JSONB path update preserves unrelated account attributes.
  # rubocop:disable Rails/SkipsModelValidations
  def remove_legacy_flag!
    Account.where(id: @account_id).update_all(
      "internal_attributes = internal_attributes - 'email_campaigns_paused'"
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  def audit!(state, action, actor_id: nil, snapshot: nil)
    EmailReputationAudit.create!(
      account_id: @account_id,
      action: action,
      actor_id: actor_id,
      snapshot: snapshot || payload(state).merge(override: state.override)
    )
  end

  def payload(state)
    EmailCampaigns::Reputation::Payload.for_state(state)
  end
end
