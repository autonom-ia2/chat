# Reunião sem provedor de calendário (#1188): WhatsApp (vídeo ou voz), link do agente ou presencial.
#
# Mesma interface de `Crm::Meetings::Creator` (que desvia para cá quando o local pedido não é Meet/Teams), mas sem
# chamada externa: nasce direto `scheduled`, com convidado alcançável por e-mail OU telefone, lembrete do agente,
# próximo vencimento do card, atividade `meeting_scheduled` e invalidação do cache de disponibilidade da caixa (se
# houver caixa).
#
# params: title, description, starts_at, ends_at, timezone, reminder_minutes_before, extra_guests (e-mails),
# location_type, location_url (custom_link), location_address (in_person), location_label, guest_phone, source,
# booking_profile_id, booking_link_id, booking_request_id (chave do pedido da página nova), consent ({ accepted_at, text_key }).
class Crm::Meetings::InternalCreator
  DEFAULT_REMINDER_MINUTES = 15
  LOCATION_TYPES = %w[whatsapp_video whatsapp_voice custom_link in_person].freeze

  def initialize(account:, card:, inbox:, scheduled_by:, params:)
    @account = account
    @card = card
    @inbox = inbox
    @scheduled_by = scheduled_by
    @params = params
  end

  def perform
    params = Crm::Meetings::Sanitizer.new(@params).sanitize!
    location_type = resolve_location_type!(params)
    guests = build_guest_list(params)
    raise ArgumentError, 'no_reachable_guest' if guests.empty?

    meeting = ActiveRecord::Base.transaction { create_meeting!(params, location_type, guests) }
    invalidate_availability!(meeting)
    meeting.reload
  end

  private

  def resolve_location_type!(params)
    type = params[:location_type].to_s
    raise ArgumentError, 'invalid_location' unless LOCATION_TYPES.include?(type)

    type
  end

  # Rascunho sem validação e convidados antes de virar `scheduled`: a validação de "convidado alcançável" do modelo
  # olha os convidados gravados (mesmo padrão do Creator).
  def create_meeting!(params, location_type, guests)
    meeting = Crm::Meeting.new(meeting_attributes(params, location_type))
    meeting.save!(validate: false)
    persist_guests!(meeting, guests)
    meeting.update!(status: :scheduled)
    meeting.update!(reminder: create_reminder!(meeting, params))
    Crm::FollowUps::CardNextDueUpdater.update(@card)
    log_activity(meeting)
    meeting
  end

  def meeting_attributes(params, location_type)
    {
      account: @account, card: @card, inbox: @inbox, created_by: @scheduled_by,
      title: params[:title], description: params[:description],
      starts_at: params[:starts_at], ends_at: params[:ends_at], timezone: params[:timezone],
      provider: :internal, online_meeting_type: location_type, external_event_id: nil,
      online_meeting_url: location_type == 'custom_link' ? params[:location_url].presence : nil,
      source: params[:source].presence, status: :draft, metadata: meeting_metadata(params, location_type)
    }
  end

  def meeting_metadata(params, location_type)
    location = { 'type' => location_type, 'label' => params[:location_label].presence, 'address' => params[:location_address].presence }
    metadata = { 'reminder_minutes_before' => reminder_minutes_before(params), 'location' => location.compact }
    metadata['booking_profile_id'] = params[:booking_profile_id] if params[:booking_profile_id].present?
    metadata['booking_link_id'] = params[:booking_link_id] if params[:booking_link_id].present?
    metadata['booking_request_id'] = params[:booking_request_id] if params[:booking_request_id].present?
    consent = params[:consent].presence
    metadata['consent'] = { 'accepted_at' => consent[:accepted_at], 'text_key' => consent[:text_key] } if consent
    metadata
  end

  def build_guest_list(params)
    guests = []
    contact_guest = build_contact_guest(params)
    guests << contact_guest if contact_guest
    params[:extra_guests].each do |email|
      next if guests.any? { |guest| guest[:email].to_s.casecmp?(email) }

      guests << { email: email, phone_number: nil, name: nil, type: :external_email, contact_id: nil }
    end
    guests
  end

  def build_contact_guest(params)
    contact = @card.contact
    return if contact.blank?

    phone = params[:guest_phone].presence || contact.phone_number.presence
    return if contact.email.blank? && phone.blank?

    { email: contact.email.presence, phone_number: phone, name: Crm::Meetings::Sanitizer.sanitize_guest_name(contact.name),
      type: :contact_guest, contact_id: contact.id }
  end

  def persist_guests!(meeting, guests)
    guests.each do |guest|
      meeting.meeting_guests.create!(
        account: @account, email: guest[:email], phone_number: guest[:phone_number], name: guest[:name],
        guest_type: guest[:type], contact_id: guest[:contact_id], rsvp_status: :rsvp_pending
      )
    end
  end

  def create_reminder!(meeting, params)
    minutes = reminder_minutes_before(params)
    Crm::FollowUp.create!(
      account: @account, card: @card, conversation: @card.primary_conversation, contact: @card.contact,
      inbox: @inbox, assignee: @card.owner, created_by: @scheduled_by,
      title: meeting.title, description: meeting.description,
      due_at: meeting.starts_at - minutes.minutes, timezone: meeting.timezone,
      follow_up_type: :meeting, automation_mode: :reminder_only, status: :pending,
      metadata: { 'source' => 'crm_meeting', 'meeting_id' => meeting.id, 'online_meeting_url' => meeting.online_meeting_url,
                  'reminder_minutes_before' => minutes }
    )
  end

  def log_activity(meeting)
    Crm::ActivityLogger.new(
      card: @card, actor: @scheduled_by, event_type: 'meeting_scheduled', conversation: @card.primary_conversation,
      payload: {
        meeting_id: meeting.id, title: meeting.title, starts_at: meeting.starts_at.iso8601,
        online_meeting_url: meeting.online_meeting_url, provider: meeting.provider,
        location_type: meeting.online_meeting_type, guests_count: meeting.meeting_guests.size
      }
    ).perform
  end

  def invalidate_availability!(meeting)
    return if meeting.inbox_id.blank?

    day = meeting.starts_at.in_time_zone(meeting.timezone.presence || 'UTC').to_date.to_s
    Crm::Meetings::AvailabilityService.invalidate(inbox_id: meeting.inbox_id, date: day, timezone: meeting.timezone)
  end

  def reminder_minutes_before(params)
    value = params[:reminder_minutes_before].presence || DEFAULT_REMINDER_MINUTES
    value.to_i.positive? ? value.to_i : DEFAULT_REMINDER_MINUTES
  end
end
