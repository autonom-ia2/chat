require 'set'

class Crm::Meetings::Creator
  DEFAULT_REMINDER_MINUTES = 15

  ProviderMeeting = Struct.new(
    :id, :title, :description, :starts_at, :ends_at, :timezone, :metadata, :inbox, :participants,
    keyword_init: true
  ) do
    def email_channel
      inbox.channel
    end
  end

  def initialize(account:, card:, inbox:, scheduled_by:, params:)
    @account = account
    @card = card
    @inbox = inbox
    @scheduled_by = scheduled_by
    @params = params
  end

  def perform
    return internal_creator.perform if internal_location?

    sanitized_params = Crm::Meetings::Sanitizer.new(@params).sanitize!
    guests = build_guest_list(sanitized_params)

    validate_email_reachable_guest!(guests)
    validate_calendar_inbox!

    meeting = create_draft_meeting!(sanitized_params)

    unless meeting.external_event_id.present?
      provider_result = call_provider_api(meeting, sanitized_params, guests)
      finalize_meeting!(meeting, sanitized_params, guests, provider_result)
    end

    invalidate_availability!(meeting)
    meeting.reload
  rescue StandardError => e
    mark_failed!(meeting, e) if meeting&.persisted? && meeting.reload.external_event_id.blank?
    raise
  end

  private

  # Agendamento WhatsApp-first (#1188): local pedido que não é Meet/Teams vira reunião interna, sem provedor.
  # Sem `location_type` nos params o fluxo Google/Microsoft segue idêntico.
  def internal_location?
    type = @params[:location_type].presence || @params['location_type'].presence
    type.present? && %w[google_meet teams].exclude?(type.to_s)
  end

  def internal_creator
    Crm::Meetings::InternalCreator.new(account: @account, card: @card, inbox: @inbox, scheduled_by: @scheduled_by, params: @params)
  end

  def build_guest_list(params)
    guests = []
    if @card.contact&.email.present?
      guests << {
        email: @card.contact.email,
        name: Crm::Meetings::Sanitizer.sanitize_guest_name(@card.contact.name),
        type: :contact_guest,
        contact_id: @card.contact.id
      }
    end

    params[:extra_guests].each do |email|
      guests << { email: email, name: nil, type: :external_email, contact_id: nil }
    end

    deduplicate_guests(guests)
  end

  def deduplicate_guests(guests)
    seen = Set.new
    guests.each_with_object([]) do |guest, deduplicated|
      key = guest[:email].to_s.downcase
      next if key.blank? || seen.include?(key)

      seen << key
      deduplicated << guest
    end
  end

  def validate_email_reachable_guest!(guests)
    return if guests.any? { |guest| guest[:email].present? }

    raise ArgumentError, 'no_email_reachable_guest'
  end

  def validate_calendar_inbox!
    return if calendar_channel&.calendar_enabled? && (calendar_channel.microsoft? || calendar_channel.google?)

    raise ArgumentError, 'unsupported_calendar_inbox'
  end

  # Bust the free/busy cache for this mailbox/day so the just-booked slot shows as
  # busy on the next scheduler open (instead of staying stale for up to the TTL).
  def invalidate_availability!(meeting)
    return if meeting.inbox_id.blank? || meeting.starts_at.blank?

    day = meeting.starts_at.in_time_zone(meeting.timezone.presence || 'UTC').to_date.to_s
    Crm::Meetings::AvailabilityService.invalidate(
      inbox_id: meeting.inbox_id, date: day, timezone: meeting.timezone
    )
  end

  def create_draft_meeting!(params)
    ActiveRecord::Base.transaction do
      meeting = Crm::Meeting.new(
        account: @account,
        card: @card,
        inbox: @inbox,
        created_by: @scheduled_by,
        title: params[:title],
        description: params[:description],
        starts_at: params[:starts_at],
        ends_at: params[:ends_at],
        timezone: params[:timezone],
        provider: resolve_provider,
        online_meeting_type: online_type(resolve_provider),
        external_event_id: nil,
        online_meeting_url: nil,
        status: :draft,
        metadata: draft_metadata(params)
      )
      meeting.save!(validate: false)
      meeting
    end
  end

  def call_provider_api(meeting, params, guests)
    if calendar_channel.microsoft?
      Microsoft::CalendarEventService.new(meeting: provider_meeting(meeting, guests)).create
    elsif calendar_channel.google?
      Google::CalendarEventService.new(channel: calendar_channel, meeting_params: google_meeting_params(meeting, params), guests: guests).create
    else
      raise ArgumentError, 'unsupported_calendar_provider'
    end
  end

  def provider_meeting(meeting, guests)
    ProviderMeeting.new(
      id: meeting.id,
      title: meeting.title,
      description: meeting.description,
      starts_at: meeting.starts_at,
      ends_at: meeting.ends_at,
      timezone: meeting.timezone,
      metadata: meeting.metadata,
      inbox: @inbox,
      participants: guests
    )
  end

  def google_meeting_params(meeting, params)
    params.merge(meeting_id: meeting.id, card_id: @card.id, reminder_minutes: reminder_minutes_before(params))
  end

  def finalize_meeting!(meeting, params, guests, provider_result)
    ActiveRecord::Base.transaction do
      meeting.lock!
      unless meeting.external_event_id.present?
        persist_guests!(meeting, guests)
        meeting.update!(
          external_event_id: provider_external_event_id(provider_result),
          online_meeting_url: provider_online_meeting_url(provider_result),
          status: :scheduled
        )
        reminder = create_reminder!(meeting, params)
        meeting.update!(reminder: reminder)
        Crm::FollowUps::CardNextDueUpdater.update(@card)
        log_activity(meeting)
      end
    end
  end

  def persist_guests!(meeting, guests)
    guests.each do |guest|
      meeting.meeting_guests.create!(
        account: @account,
        email: guest[:email],
        name: guest[:name],
        guest_type: guest[:type],
        contact_id: guest[:contact_id],
        rsvp_status: :rsvp_pending
      )
    end
  end

  def create_reminder!(meeting, params)
    reminder_minutes = reminder_minutes_before(params)
    Crm::FollowUp.create!(
      account: @account,
      card: @card,
      conversation: @card.primary_conversation,
      contact: @card.contact,
      inbox: @inbox,
      assignee: @card.owner,
      created_by: @scheduled_by,
      title: meeting.title,
      description: meeting.description,
      due_at: meeting.starts_at - reminder_minutes.minutes,
      timezone: meeting.timezone,
      follow_up_type: :meeting,
      automation_mode: :reminder_only,
      status: :pending,
      metadata: {
        'source' => 'crm_meeting',
        'meeting_id' => meeting.id,
        'online_meeting_url' => meeting.online_meeting_url,
        'reminder_minutes_before' => reminder_minutes
      }
    )
  end

  def log_activity(meeting)
    Crm::ActivityLogger.new(
      card: @card,
      actor: @scheduled_by,
      event_type: 'meeting_scheduled',
      conversation: @card.primary_conversation,
      payload: {
        meeting_id: meeting.id,
        title: meeting.title,
        starts_at: meeting.starts_at.iso8601,
        online_meeting_url: meeting.online_meeting_url,
        provider: meeting.provider,
        guests_count: meeting.meeting_guests.size
      }
    ).perform
  end

  def provider_external_event_id(result)
    value = provider_value(result, :external_event_id)
    raise StandardError, 'calendar_provider_missing_event_id' if value.blank?

    value
  end

  def provider_online_meeting_url(result)
    value = provider_value(result, :online_meeting_url).presence || provider_value(result, :join_url).presence || provider_value(result, :hangoutLink)
    raise StandardError, 'calendar_provider_missing_join_url' if value.blank?

    value
  end

  def provider_value(result, key)
    return result.public_send(key) if result.respond_to?(key)
    return unless result.respond_to?(:[])

    result[key] || result[key.to_s]
  end

  def mark_failed!(meeting, error)
    metadata = (meeting.metadata || {}).merge('error' => error.message.to_s.truncate(500))
    meeting.update_columns(status: Crm::Meeting.statuses[:failed], metadata: metadata, updated_at: Time.current)
  end

  def draft_metadata(params)
    { 'reminder_minutes_before' => reminder_minutes_before(params) }
  end

  def reminder_minutes_before(params)
    value = params[:reminder_minutes_before].presence || DEFAULT_REMINDER_MINUTES
    value.to_i.positive? ? value.to_i : DEFAULT_REMINDER_MINUTES
  end

  def resolve_provider
    calendar_channel.microsoft? ? :microsoft : :google
  end

  def online_type(provider)
    provider == :microsoft ? :teams : :google_meet
  end

  def calendar_channel
    @calendar_channel ||= @inbox.channel if @inbox.channel.is_a?(Channel::Email)
  end
end
