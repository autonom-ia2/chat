class Sla::EvaluateAppliedSlaService
  pattr_initialize [:applied_sla!]

  def perform
    # Choke point definitivo do processamento de SLA: nenhum SlaEvent é criado quando a conta não tem
    # a feature `sla` (cobre o job folha ProcessAppliedSlaJob e qualquer invocação direta, mesmo que o
    # applied_sla tenha sido criado quando a flag ainda estava ligada).
    return unless applied_sla.account.feature_enabled?('sla')
    # Upstream 4.17 (orthogonal to the fork engine): conversations of blocked contacts freeze —
    # no breaches accrue and the resolved hit/missed path is not evaluated.
    return unless applied_sla.conversation.sla_applicable?

    check_sla_thresholds

    # We will calculate again in the next iteration
    return unless applied_sla.conversation.resolved?

    # after conversation is resolved, we will check if the SLA was hit or missed
    handle_hit_sla(applied_sla)
  end

  private

  def check_sla_thresholds
    [:first_response_time_threshold, :next_response_time_threshold, :resolution_time_threshold].each do |threshold|
      next if applied_sla.sla_policy.send(threshold).blank?

      send("check_#{threshold}", applied_sla, applied_sla.conversation, applied_sla.sla_policy)
    end
  end

  def check_first_response_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    return if first_reply_was_within_threshold?(conversation)
    return unless due_at_reached?(due_at_values[:frt])

    handle_missed_sla(applied_sla, 'frt')
  end

  # Same clock as the card (issue #283): a first reply at or before frt_due_at is on time.
  def first_reply_was_within_threshold?(conversation)
    return false if conversation.first_reply_created_at.blank?

    due_at = due_at_values[:frt]
    due_at.nil? || conversation.first_reply_created_at.to_i <= due_at
  end

  def check_next_response_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    # still waiting for first reply, so covered under first response time threshold
    return if conversation.first_reply_created_at.blank?
    # Waiting on customer response, no need to check next response time threshold
    return if conversation.waiting_since.blank?
    return unless due_at_reached?(due_at_values[:nrt])

    handle_missed_sla(applied_sla, 'nrt')
  end

  def get_last_message_id(conversation)
    # TODO: refactor the method to fetch last message without reply
    conversation.messages.where(message_type: :incoming).last&.id
  end

  def already_missed?(applied_sla, type, meta = {})
    SlaEvent.exists?(applied_sla: applied_sla, event_type: type, meta: meta)
  end

  def check_resolution_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    return if conversation.resolved?
    return unless due_at_reached?(due_at_values[:rt])

    handle_missed_sla(applied_sla, 'rt')
  end

  # The deadline is the one the card shows (AppliedSla#calculate_due_at via Sla::DueAtCalculator),
  # so the breach is recorded at the very instant the card says the SLA is due. A nil deadline
  # (not reachable within the calculator horizon) never breaches.
  def due_at_reached?(due_at)
    due_at.present? && Time.zone.now.to_i >= due_at
  end

  # Memoized per perform run: the three thresholds share one calendar lookup.
  def due_at_values
    @due_at_values ||= applied_sla.due_at_values
  end

  # Defensive Wave-2 skip: group conversations stop accruing breaches but the
  # resolved hit/missed path (handle_hit_sla via perform) stays untouched.
  def skip_group_thresholds?(conversation, sla_policy)
    sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(conversation)
  end

  def handle_missed_sla(applied_sla, type, meta = {})
    meta = { message_id: get_last_message_id(applied_sla.conversation) } if type == 'nrt'
    return if already_missed?(applied_sla, type, meta)
    # Wave-3 AI breach guard: runs ONLY at the exact moment a breach would be
    # recorded (after the already_missed? cache, before creating the SlaEvent).
    return if Sla::AiBreachGuard.new(applied_sla: applied_sla, breach_type: type).skip_breach?

    create_sla_event(applied_sla, type, meta)
    Rails.logger.warn "SLA #{type} missed for conversation #{applied_sla.conversation.id} " \
                      "in account #{applied_sla.account_id} " \
                      "for sla_policy #{applied_sla.sla_policy.id}"

    applied_sla.update!(sla_status: 'active_with_misses') if applied_sla.sla_status != 'active_with_misses'
  end

  def handle_hit_sla(applied_sla)
    if applied_sla.active?
      applied_sla.update!(sla_status: 'hit')
      Rails.logger.info "SLA hit for conversation #{applied_sla.conversation.id} " \
                        "in account #{applied_sla.account_id} " \
                        "for sla_policy #{applied_sla.sla_policy.id}"
    else
      applied_sla.update!(sla_status: 'missed')
      Rails.logger.info "SLA missed for conversation #{applied_sla.conversation.id} " \
                        "in account #{applied_sla.account_id} " \
                        "for sla_policy #{applied_sla.sla_policy.id}"
    end
  end

  def create_sla_event(applied_sla, event_type, meta = {})
    SlaEvent.create!(
      applied_sla: applied_sla,
      conversation: applied_sla.conversation,
      event_type: event_type,
      meta: meta,
      account: applied_sla.account,
      inbox: applied_sla.conversation.inbox,
      sla_policy: applied_sla.sla_policy
    )
  end
end
