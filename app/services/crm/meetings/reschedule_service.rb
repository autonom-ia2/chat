class Crm::Meetings::RescheduleService
  DEFAULT_REMINDER_MINUTES = 15

  # propagate:false — apply the new time LOCALLY only, skipping the provider call.
  # Used by the 2-way sync (S7) when the change ORIGINATED in the provider calendar,
  # so we must not echo it back (no loop). Default true = unchanged behavior.
  def initialize(meeting:, params:, propagate: true)
    @meeting = meeting
    @params = params.with_indifferent_access
    @propagate = propagate
  end

  def perform
    old_local_date = local_date(@meeting.starts_at)

    @meeting.with_lock do
      validate_reschedulable!
      validate_times!

      # Local writes first, provider call LAST — all inside the row-locked
      # transaction. A provider failure raises and rolls back the local changes,
      # so the row never diverges from the provider. The lock serializes
      # concurrent reschedule/cancel requests (re-validates after the reload).
      # Status stays :scheduled so the meeting keeps rendering on the calendar
      # and stays actionable (the reschedule history lives in the activity log).
      @meeting.update!(
        starts_at: starts_at,
        ends_at: ends_at,
        timezone: timezone,
        status: :scheduled
      )
      rearm_reminder!
      reset_guest_rsvps!
      Crm::FollowUps::CardNextDueUpdater.update(@meeting.card)
      # Reunião da página de agendamento nova (#1192): confirmação volta a pendente e os avisos no WhatsApp vão para o
      # novo horário, venha a mudança do cliente, do painel ou da agenda do provedor. Na mesma transação: se o
      # provedor falhar, nada muda.
      Crm::BookingV2::Notices::Scheduler.meeting_moved!(@meeting)

      update_provider_event! unless skip_provider_call?
    end

    invalidate_availability!(old_local_date)
    log_activity
    @meeting.reload
  end

  private

  attr_reader :meeting

  # Bust the free/busy cache for both the old and new day so the freed/taken slot
  # shows up on the next scheduler open instead of staying stale.
  def invalidate_availability!(old_local_date)
    return if @meeting.inbox_id.blank?

    [old_local_date, local_date(@meeting.starts_at)].compact.uniq.each do |day|
      Crm::Meetings::AvailabilityService.invalidate(
        inbox_id: @meeting.inbox_id, date: day, timezone: @meeting.timezone
      )
    end
  end

  def local_date(time)
    return if time.blank?

    time.in_time_zone(@meeting.timezone.presence || 'UTC').to_date.to_s
  end

  def starts_at
    @starts_at ||= @params[:starts_at]
  end

  def ends_at
    @ends_at ||= @params[:ends_at]
  end

  def timezone
    @timezone ||= @params[:timezone].presence || @meeting.timezone
  end

  def validate_reschedulable!
    return if @meeting.scheduled? || @meeting.rescheduled?

    raise ArgumentError, 'meeting_not_reschedulable'
  end

  def validate_times!
    raise ArgumentError, 'starts_at_required' if starts_at.blank?
    raise ArgumentError, 'ends_at_required' if ends_at.blank?
    raise ArgumentError, 'ends_at_must_be_after_starts_at' unless ends_at > starts_at
  end

  def skip_provider_call?
    return true unless @propagate

    external_id = @meeting.external_event_id
    external_id.blank? || external_id.to_s.start_with?('sim-') ||
      (@meeting.google? && Crm::Config.calendar_google_simulate?) ||
      (@meeting.microsoft? && Crm::Config.calendar_ms_simulate?)
  end

  def update_provider_event!
    attributes = { starts_at: starts_at, ends_at: ends_at, timezone: timezone }

    if @meeting.microsoft?
      Microsoft::CalendarEventService.new(meeting: @meeting).update_event(@meeting.external_event_id, attributes)
    elsif @meeting.google?
      Google::CalendarEventService.new(channel: @meeting.email_channel, meeting_params: {}, guests: [])
                                  .update_event(@meeting.external_event_id, attributes)
    end
  end

  def rearm_reminder!
    reminder = @meeting.reminder
    return if reminder.blank?

    reminder.update!(
      due_at: starts_at - reminder_minutes.minutes,
      timezone: timezone,
      status: :pending
    )
  end

  def reminder_minutes
    metadata = (@meeting.reminder&.metadata || @meeting.metadata || {})
    value = metadata['reminder_minutes_before'].presence || DEFAULT_REMINDER_MINUTES
    value.to_i.positive? ? value.to_i : DEFAULT_REMINDER_MINUTES
  end

  def reset_guest_rsvps!
    @meeting.meeting_guests.where.not(rsvp_status: :rsvp_pending)
            .update_all(rsvp_status: Crm::MeetingGuest.rsvp_statuses[:rsvp_pending], updated_at: Time.current)
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: @meeting.card,
      actor: @meeting.created_by,
      event_type: 'meeting_rescheduled',
      conversation: @meeting.card.primary_conversation,
      payload: {
        meeting_id: @meeting.id,
        title: @meeting.title,
        starts_at: @meeting.starts_at.iso8601,
        online_meeting_url: @meeting.online_meeting_url,
        provider: @meeting.provider
      }
    ).perform
  end
end
