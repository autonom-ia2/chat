class EmailCampaigns::Reputation::Evaluator
  FLAG_KEY = 'email_campaigns_paused'.freeze

  def initialize(account, policy: EmailCampaigns::Reputation::Policy.new)
    @account_id = account.id
    @policy = policy
  end

  def evaluate!
    observed do |account, state, observation|
      refresh!(account, state, observation)
      payload(state)
    end
  end

  def resume!(actor: nil, delivery_mode: 'ses')
    observed do |account, state, observation|
      refresh!(account, state, observation)
      provider = EmailCampaigns::Reputation::ProviderGate.protection if delivery_mode.to_s == 'ses'
      result = payload(state)
      next result.merge(resume_allowed: false, protection: provider) if provider

      release!(state, actor) if result[:resume_allowed]
      result = payload(state)
      yield if result[:resume_allowed] && block_given?
      result
    end
  end

  def override!(actor:, reason:, duration_seconds:, message_budget:)
    # STI type is read from the database; account roles and request params cannot grant this.
    raise Pundit::NotAuthorizedError unless actor && SuperAdmin.exists?(id: actor.id)

    duration, budget = validate_override!(reason, duration_seconds, message_budget)

    observed do |account, state, observation|
      refresh!(account, state, observation)
      raise CustomExceptions::EmailReputationOverride, 'override requires a protected account' unless state.blocked

      provider = EmailCampaigns::Reputation::ProviderGate.protection
      next payload(state).merge(resume_allowed: false, protection: provider) if provider

      state.update!(override: {
                      actor_id: actor.id, reason: reason.strip, granted_at: Time.current.iso8601,
                      expires_at: (Time.current + duration).iso8601, remaining: budget, message_budget: budget,
                      feedback_fingerprint: observation.fingerprint
                    })
      audit!(state, 'override_granted', actor_id: actor.id)
      payload(state)
    end
  end

  private

  def release!(state, actor)
    return unless state.blocked && !state.override_active?

    state.update!(blocked: false)
    mirror_flag!(nil)
    audit!(state, 'released', actor_id: actor&.id)
  end

  # Collection never holds Account/state locks. A later observation or committed feedback
  # invalidates this generation. In particular, stale resume/override requests fail closed.
  def observed
    observation = EmailCampaigns::Reputation::Observation.new(@account_id).collect
    account = Account.find(@account_id)
    account.with_lock do
      state = EmailReputationState.find_by!(account_id: @account_id)
      state.with_lock do
        unless observation.current?(state)
          next payload(state).merge(resume_allowed: false,
                                    protection: { kind: 'technical', code: 'reputation_evaluation_superseded', overridable: false })
        end
        yield account, state, observation
      end
    end
  end

  def refresh!(account, state, observation)
    metrics = observation.metrics
    decision = @policy.evaluate(metrics)
    should_pause = @policy.mode == 'enforce' ? decision[:pause] : EmailCampaigns::Reputation::LegacyDecision.pause?(metrics)
    if @policy.mode != 'enforce'
      decision[:resume_allowed] = EmailCampaigns::Reputation::LegacyDecision.resume_allowed?(metrics, proposed: decision[:resume_allowed])
    end
    published = metrics.merge(decision).merge(evaluation_generation: observation.generation)
    state.assign_attributes(current_metrics: published.stringify_keys, policy: @policy.snapshot,
                            evaluated_at: Time.current, level: decision[:level], evaluated_feedback_version: observation.feedback_version)
    record_alert!(state)
    revoke_override!(state, observation.fingerprint)
    persist_protection!(state, account.internal_attributes[FLAG_KEY], should_pause)
  end

  def persist_protection!(state, legacy, should_pause)
    pause!(state, legacy) if !state.blocked && (legacy.present? || should_pause)
    state.save!
    # Re-establish the compatibility mirror if older application code cleared it.
    mirror_flag!({ at: state.triggered_at, reason: 'email_reputation_protection' }) if state.blocked && legacy.blank?
  end

  # Durable alerts for the UI/operations consumer; no external notification side effects.
  def record_alert!(state)
    return if @policy.mode == 'shadow'

    previous = state.current_metrics_in_database
    current = state.current_metrics
    risk_changed = state.will_save_change_to_level? && state.level != 'healthy'
    new_complaint = current.fetch('complaints') > previous.fetch('complaints', 0)
    audit!(state, 'risk_alert') if risk_changed || new_complaint
  end

  def pause!(state, legacy)
    snapshot = EmailCampaigns::Reputation::Snapshot.capture(state, legacy)
    state.assign_attributes(blocked: true, triggered_at: snapshot.fetch(:triggered_at), trigger_snapshot: snapshot, override: {})
    audit!(state, 'paused', snapshot: snapshot)
  end

  def validate_override!(reason, duration_seconds, message_budget)
    duration = Integer(duration_seconds.to_s, 10)
    budget = Integer(message_budget.to_s, 10)
    valid_reason = reason.is_a?(String) && reason.strip.length.between?(10, 500)
    raise ArgumentError, 'invalid override bounds/reason' unless duration.between?(1, 3600) && budget.between?(1, 50) && valid_reason

    [duration, budget]
  rescue ArgumentError => e
    raise CustomExceptions::EmailReputationOverride, e.message
  end

  def revoke_override!(state, fingerprint)
    return if state.override.blank? || state.override['revoked_at']

    reason = if fingerprint != state.override.fetch('feedback_fingerprint')
               'new_harmful_feedback'
             elsif Time.iso8601(state.override.fetch('expires_at')) <= Time.current
               'expired'
             elsif state.override.fetch('remaining').zero?
               'budget_exhausted'
             end
    return unless reason

    state.override = state.override.merge('revoked_at' => Time.current.iso8601, 'revocation_reason' => reason)
    audit!(state, 'override_revoked')
  end

  # Atomic JSONB path updates must preserve concurrently written unrelated account attributes.
  # rubocop:disable Rails/SkipsModelValidations
  def mirror_flag!(value)
    if value
      expression = "internal_attributes = jsonb_set(internal_attributes, '{email_campaigns_paused}', ?::jsonb)"
      Account.where(id: @account_id).update_all([expression, value.to_json])
    else
      Account.where(id: @account_id).update_all("internal_attributes = internal_attributes - 'email_campaigns_paused'")
    end
  end

  # rubocop:enable Rails/SkipsModelValidations

  def audit!(state, action, actor_id: nil, snapshot: nil)
    EmailReputationAudit.create!(account_id: @account_id, action: action, actor_id: actor_id,
                                 snapshot: snapshot || payload(state).merge(override: state.override))
  end

  def payload(state)
    EmailCampaigns::Reputation::Payload.for_state(state)
  end
end
