class Api::V1::Accounts::Crm::CalendarController < Api::V1::Accounts::Crm::BaseController
  def events
    authorize ::Crm::FollowUp, :index?
    render json: { payload: follow_up_events + expected_close_events + meeting_events + external_events }
  end

  # Read-only free/busy lookup for the meeting scheduler. Returns the busy
  # intervals of the chosen mailbox for a single day so the FE can disable
  # conflicting time slots. Gated on the meetings flag; fail-safe (empty busy).
  def available_slots
    authorize ::Crm::FollowUp, :index?
    return render json: { error: 'crm.calendar_meetings.disabled' }, status: :not_found unless Crm::Config.calendar_meetings_enabled?(Current.account)

    inbox = Current.account.inboxes.find(params[:inbox_id])
    # Pass the current agent so a SHARED mailbox shows THIS agent's availability
    # (per-agent), consistent with the public booking page. Dedicated mailbox =
    # unchanged (real provider free/busy).
    busy = Crm::Meetings::AvailabilityService.new(
      inbox: inbox,
      date: availability_date,
      timezone: availability_timezone,
      agent: Current.user
    ).busy_intervals

    render json: { payload: { busy: busy, date: availability_date, timezone: availability_timezone } }
  end

  private

  def availability_date
    @availability_date ||= parse_availability_date.to_s
  end

  def parse_availability_date
    Date.iso8601(params[:date].to_s)
  rescue ArgumentError, TypeError
    Time.zone.today
  end

  def availability_timezone
    @availability_timezone ||=
      ActiveSupport::TimeZone[params[:timezone].to_s].present? ? params[:timezone].to_s : 'UTC'
  end

  def follow_up_events
    filtered_follow_ups.order(:due_at, :id).limit(limit).map do |follow_up|
      {
        id: "follow_up_#{follow_up.id}",
        event_type: "follow_up_#{follow_up.automation_mode}",
        title: follow_up.title,
        starts_at: follow_up.due_at&.iso8601,
        status: follow_up.status,
        card_id: follow_up.card_id,
        conversation_id: visible_conversation_id(follow_up),
        contact_id: follow_up.contact_id,
        inbox_id: follow_up.inbox_id,
        assignee_id: follow_up.assignee_id
      }
    end
  end

  def expected_close_events
    filtered_cards.where.not(expected_close_at: nil).order(:expected_close_at, :id).limit(limit).map do |card|
      {
        id: "expected_close_#{card.id}",
        event_type: 'expected_close',
        title: card.title,
        starts_at: card.expected_close_at&.iso8601,
        status: card.status,
        card_id: card.id,
        conversation_id: visible_card_conversation_id(card),
        contact_id: card.contact_id,
        inbox_id: card.inbox_id,
        assignee_id: card.owner_id
      }
    end
  end

  def meeting_events
    return [] unless Crm::Config.calendar_meetings_enabled?(Current.account)

    filtered_meetings.scheduled.order(:starts_at, :id).limit(limit).map do |meeting|
      {
        id: "meeting_#{meeting.id}",
        event_type: 'meeting',
        title: meeting.title,
        starts_at: meeting.starts_at&.iso8601,
        ends_at: meeting.ends_at&.iso8601,
        status: meeting.status,
        card_id: meeting.card_id,
        conversation_id: visible_card_conversation_id(meeting.card),
        contact_id: meeting.card&.contact_id,
        inbox_id: meeting.inbox_id,
        assignee_id: meeting.card&.owner_id,
        provider: meeting.provider,
        online_meeting_type: meeting.online_meeting_type,
        online_meeting_url: meeting.online_meeting_url,
        guests_count: meeting.meeting_guests.size,
        # Página de agendamento (#1192): selo de confirmação do cliente no popover.
        booking: meeting.booking?,
        confirmation_status: meeting.confirmation_status,
        notices_stopped: meeting.reminders_stopped_at.present?
      }
    end
  end

  # Read-only external calendar events (the agent's OWN Google/MS meetings created
  # outside the CRM) for the SAME from/to window the endpoint already parses. Gated
  # on the meetings flag and bounded to a valid window; fail-safe (empty on error).
  def external_events
    return [] unless Crm::Config.calendar_meetings_enabled?(Current.account)

    from = meeting_filter_time(:from)
    to = meeting_filter_time(:to)
    return [] if from.blank? || to.blank?

    Crm::Calendar::ExternalEventsService.new(
      account: Current.account, inboxes: visible_calendar_inboxes, time_min: from, time_max: to
    ).events
  end

  # Only the calendar-enabled mailboxes the current user may see (Pundit scope:
  # admins → all account inboxes, agents → their member inboxes) — so an agent
  # never receives another mailbox's external calendar titles/times.
  def visible_calendar_inboxes
    policy_scope(::Inbox).select do |inbox|
      channel = inbox.channel
      channel.is_a?(Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
    end
  end

  def filtered_follow_ups
    scope = ::Crm::FollowUps::FilterQuery.new(
      scope: policy_scope(::Crm::FollowUp),
      params: params,
      includes: [:card, { conversation: :conversation_participants }]
    ).perform
    # Hide completed/canceled follow-ups by default — they crowd out upcoming
    # ones once the date-ordered cap is reached. The calendar passes
    # include_completed=true (the "Histórico" toggle) to show them.
    include_completed? ? scope : scope.active
  end

  def include_completed?
    ActiveModel::Type::Boolean.new.cast(params[:include_completed])
  end

  def filtered_cards
    ::Crm::Cards::CalendarQuery.new(scope: policy_scope(::Crm::Card), params: params).perform
  end

  def filtered_meetings
    scope = Current.account.crm_meetings
                           .where(card_id: policy_scope(::Crm::Card).select(:id))
                           .includes(:meeting_guests, card: { primary_conversation: :conversation_participants })
    scope = scope.joins(:card).where(crm_cards: { pipeline_id: params[:pipeline_id] }) if params[:pipeline_id].present?
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope = scope.joins(:card).where(crm_cards: { owner_id: owner_id }) if owner_id.present?
    scope = scope.where('crm_meetings.starts_at >= ?', meeting_filter_time(:from)) if meeting_filter_time(:from).present?
    scope = scope.where('crm_meetings.starts_at <= ?', meeting_filter_time(:to)) if meeting_filter_time(:to).present?
    scope
  end

  def owner_id
    params[:owner_id].presence || params[:assignee_id].presence
  end

  def meeting_filter_time(key)
    @meeting_filter_time ||= {}
    @meeting_filter_time[key] ||= safe_meeting_filter_time(params[key]) if params[key].present?
  rescue ArgumentError, TypeError
    @meeting_filter_time[key] = nil
  end

  def safe_meeting_filter_time(raw_value)
    parsed_value = Time.zone.parse(raw_value)
    return if parsed_value.blank?
    return unless parsed_value.year.between?(1900, 9999)

    parsed_value
  end

  def visible_conversation_id(follow_up)
    return if follow_up.conversation.blank?
    return follow_up.conversation_id if conversation_visibility.visible?(follow_up.conversation)
  end

  def visible_card_conversation_id(card)
    return if card.primary_conversation.blank?
    return card.conversation_id if conversation_visibility.visible?(card.primary_conversation)
  end

  def conversation_visibility
    @conversation_visibility ||= Crm::Conversations::Visibility.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    )
  end

  def limit
    params.fetch(:limit, 2000).to_i.clamp(1, 2000)
  end
end
