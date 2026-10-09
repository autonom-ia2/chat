# Reserva de horário da página nova (#1188), usada pelo link público, pelo convite e pela IA.
#
# Sob lock de agente (`pg_advisory_xact_lock(2, host_id)`) e, se a página tem caixa, antes o lock da caixa
# (`1, inbox_id`): mesma ordem do v1, que também passa a tomar o lock de agente, então v1 e v2 do mesmo responsável
# não marcam o mesmo horário. Dentro do lock: idempotência (mesmo telefone + mesmo início + mesma página nos últimos
# 5 minutos devolve a reunião já criada), limite de reuniões abertas por telefone, reconferência estrita do horário,
# contato, card e reunião.
#
# Erros: ArgumentError com código (invalid_name, invalid_phone, invalid_email, invalid_starts_at, invalid_duration,
# slot_unavailable, availability_unavailable, host_unavailable, invalid_location, too_many_open,
# no_pipeline_configured, no_stage_configured).
class Crm::BookingV2::Booker
  Result = Struct.new(:meeting, :contact, :card, :existing, keyword_init: true)

  MAX_NAME_LENGTH = 120
  MAX_EMAIL_LENGTH = 254
  MAX_OPEN_MEETINGS = 2
  IDEMPOTENCY_WINDOW = 5.minutes
  LOCK_NS_INBOX = 1
  LOCK_NS_AGENT = 2
  DEFAULT_REMINDER_MINUTES = 15
  PROVIDER_LOCATIONS = %w[google_meet teams].freeze

  # Interface pedida pelo plano (#1188): um argumento nomeado por dado do formulário.
  def initialize(profile:, host:, name:, phone:, starts_at:, source:, email: nil, duration: nil, location_type: nil, # rubocop:disable Metrics/ParameterLists
                 consent: {}, conversation: nil, link: nil)
    @profile = profile
    @account = profile.account
    @host = host
    @raw = { name: name, phone: phone, starts_at: starts_at, email: email, duration: duration, location_type: location_type }
    @source = source.to_s
    @consent = consent.to_h.with_indifferent_access
    @conversation = conversation
    @link = link if link&.booking_profile_id == profile.id
  end

  def perform
    validate_inputs!
    result = ActiveRecord::Base.transaction do
      acquire_locks!
      existing_result || book!
    end
    broadcast_card_created(result.card) unless result.existing
    result
  end

  private

  attr_reader :profile, :host, :account

  def validate_inputs!
    raise ArgumentError, 'invalid_name' if name.blank?
    raise ArgumentError, 'invalid_phone' if phone.blank?
    raise ArgumentError, 'invalid_email' if @raw[:email].present? && email.blank?

    starts_at
    raise ArgumentError, 'invalid_duration' unless profile.durations.include?(duration_minutes)

    location
    raise ArgumentError, 'host_unavailable' unless Crm::BookingV2::HostEligibility.eligible?(account: account, user: host)
  end

  def name
    @name ||= clean_text(@raw[:name]).first(MAX_NAME_LENGTH).strip
  end

  def phone
    @phone ||= Crm::BookingV2::PhoneLookup.normalize(@raw[:phone], region: Crm::BookingV2::PhoneLookup.region_for(profile.resolved_timezone))
  end

  def phone_candidates
    @phone_candidates ||= Crm::BookingV2::PhoneLookup.candidates(phone)
  end

  def email
    @email ||= clean_email(@raw[:email])
  end

  def starts_at
    @starts_at ||= Time.iso8601(@raw[:starts_at].to_s)
  rescue ArgumentError
    raise ArgumentError, 'invalid_starts_at'
  end

  def duration_minutes
    @duration_minutes ||= @raw[:duration].nil? ? profile.duration_minutes : Integer(@raw[:duration].to_s, exception: false)
  end

  # O local pedido precisa ser um dos locais da página; sem pedido, o primeiro.
  def location
    @location ||= begin
      options = Array(profile.locations).select { |item| item.is_a?(Hash) }
      wanted = @raw[:location_type].to_s.presence || options.first&.dig('type')
      options.find { |item| item['type'] == wanted } || (raise ArgumentError, 'invalid_location')
    end
  end

  def acquire_locks!
    connection = ActiveRecord::Base.connection
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_INBOX}, #{profile.inbox_id.to_i})") if profile.inbox_id.present?
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_AGENT}, #{host.id.to_i})")
  end

  def existing_result
    meeting = guest_meetings.where(starts_at: starts_at).where('crm_meetings.created_at > ?', IDEMPOTENCY_WINDOW.ago)
                            .where("crm_meetings.metadata->>'booking_profile_id' = ?", profile.id.to_s)
                            .order(:id).first
    return if meeting.nil?

    Result.new(meeting: meeting, contact: meeting.card.contact, card: meeting.card, existing: true)
  end

  def guest_meetings
    Crm::Meeting.where(account_id: account.id, status: :scheduled)
                .where(id: Crm::MeetingGuest.where(account_id: account.id, phone_number: phone_candidates).select(:meeting_id))
  end

  def book!
    raise ArgumentError, 'too_many_open' if guest_meetings.where('crm_meetings.starts_at > ?', Time.current).count >= MAX_OPEN_MEETINGS

    ensure_slot_available!
    contact = find_or_create_contact!
    card = create_card!(contact)
    meeting = create_meeting!(card)
    Result.new(meeting: meeting, contact: contact, card: card, existing: false)
  end

  def ensure_slot_available!
    local_date = starts_at.in_time_zone(profile.resolved_timezone).to_date.iso8601
    available = Crm::BookingV2::Slots.new(profile: profile, host: host, date: local_date, duration: duration_minutes, strict: true).perform
    raise ArgumentError, 'slot_unavailable' unless available.any? { |iso| Time.iso8601(iso) == starts_at }
  end

  def find_or_create_contact!
    Crm::BookingV2::PhoneLookup.find_contact(account: account, e164: phone) ||
      account.contacts.create!(name: name, phone_number: phone, email: free_email)
  end

  def free_email
    email if email.present? && account.contacts.from_email(email).blank?
  end

  def create_card!(contact)
    Crm::Cards::Creator.new(
      account: account, user: nil,
      params: {
        pipeline_id: pipeline_id, stage_id: stage_id, contact_id: contact.id, owner_id: host.id,
        conversation_id: conversation&.id, inbox_id: conversation&.inbox_id,
        title: "#{contact.name.presence || name} - #{profile.title.presence || 'Agendamento'}".first(255),
        currency: 'BRL', source: @source
      }
    ).perform
  end

  def conversation
    @conversation if @conversation.present? && @conversation.account_id == account.id && @conversation.contact&.phone_number.in?(phone_candidates)
  end

  def create_meeting!(card)
    params = meeting_params(card)
    return Crm::Meetings::InternalCreator.new(**creator_args(card), params: params).perform unless PROVIDER_LOCATIONS.include?(location['type'])

    meeting = Crm::Meetings::Creator.new(**creator_args(card), params: params.except(:location_type)).perform
    meeting.update!(source: @source.presence, metadata: meeting.metadata.merge(booking_metadata))
    meeting
  end

  def creator_args(card)
    { account: account, card: card, inbox: profile.inbox, scheduled_by: host }
  end

  def meeting_params(card)
    {
      title: profile.title.presence || card.title, description: profile.description,
      starts_at: starts_at, ends_at: starts_at + duration_minutes.minutes, timezone: profile.resolved_timezone,
      reminder_minutes_before: DEFAULT_REMINDER_MINUTES, extra_guests: extra_guests(card),
      guest_phone: phone, source: @source.presence
    }.merge(location_params, booking_metadata.symbolize_keys)
  end

  def location_params
    { location_type: location['type'], location_url: location['url'], location_address: location['address'], location_label: location['label'] }
  end

  def extra_guests(card)
    return [] if email.blank? || card.contact&.email.to_s.casecmp?(email)

    [email]
  end

  def booking_metadata
    data = { 'booking_profile_id' => profile.id, 'booking_link_id' => @link&.id }.compact
    return data if @consent.blank?

    data.merge('consent' => { 'accepted_at' => @consent[:accepted_at].presence || Time.current.iso8601, 'text_key' => @consent[:text_key] })
  end

  def pipeline_id
    profile.default_pipeline_id || default_pipeline&.id || (raise ArgumentError, 'no_pipeline_configured')
  end

  def stage_id
    return profile.default_stage_id if profile.default_stage_id.present?

    default_pipeline&.stages&.order(:position)&.first&.id || (raise ArgumentError, 'no_stage_configured')
  end

  def default_pipeline
    pipelines = account.crm_pipelines
    @default_pipeline ||= profile.default_pipeline_id ? pipelines.find_by(id: profile.default_pipeline_id) : pipelines.active.order(:id).first
  end

  # Texto puro: sem tag HTML e sem caractere de controle (vira espaço). O strip_tags devolve entidades ("&" vira
  # "&amp;"); como gravamos texto, e não HTML, desfazemos a entidade: quem mostra (Vue, views) já escapa.
  def clean_text(value)
    plain = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(value.to_s))
    plain.each_char.map { |char| char.ord < 32 || char.ord == 127 ? ' ' : char }.join
  end

  def clean_email(value)
    normalized = value.to_s.strip.downcase
    return if normalized.blank? || normalized.length > MAX_EMAIL_LENGTH

    address = Mail::Address.new(normalized).address
    normalized if address == normalized && address.include?('@') && address.split('@').last.include?('.')
  rescue Mail::Field::ParseError
    nil
  end

  # Depois do commit: o card novo aparece no Kanban e no calendário de quem está aberto (como no v1). A reserva já
  # está feita; falha aqui só é registrada.
  def broadcast_card_created(card)
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_CREATED)
  rescue StandardError => e
    Rails.logger.error("CRM booking v2 realtime broadcast failed: #{e.class.name}")
  end
end
