# Reserva de horário da página nova (#1188), usada pelo link público, pelo convite e pela IA.
#
# Responsável vem da página, nunca de quem chama: o agente do link individual (se for desta página e estiver ativo)
# ou o responsável padrão da página.
#
# Ordem: (1) reenvio idempotente devolve a reunião já criada, sem trava; (2) conferência estrita do horário COM o
# provedor (freebusy Google/Microsoft), fora das travas, porque a rede pode demorar; (3) travas, nesta ordem: caixa
# (`pg_advisory_xact_lock(1, inbox_id)`, se a página tem caixa), agente (`2, host_id`) e telefone
# (`3, crc32("conta:telefone")`) — mesma ordem do v1, que também toma a do agente, então v1 e v2 do mesmo responsável
# não marcam o mesmo horário, e duas reservas do mesmo telefone novo não criam dois contatos. Dentro das travas:
# idempotência de novo (mesmo telefone + mesmo início + mesma página nos últimos 5 minutos), limite de reuniões abertas
# por telefone, reconferência SÓ local do horário, contato, card e reunião.
#
# Erros: ArgumentError com código (invalid_name, invalid_phone, invalid_email, invalid_starts_at, invalid_duration,
# invalid_location, host_unavailable, email_required, calendar_unavailable, slot_unavailable, availability_unavailable,
# too_many_open, no_pipeline_configured, no_stage_configured).
class Crm::BookingV2::Booker
  Result = Struct.new(:meeting, :contact, :card, :existing, keyword_init: true)

  MAX_OPEN_MEETINGS = 2
  IDEMPOTENCY_WINDOW = 5.minutes
  LOCK_NS_INBOX = 1
  LOCK_NS_AGENT = 2
  LOCK_NS_PHONE = 3
  INT32_RANGE = 2**32
  INT32_MAX = (2**31) - 1
  DEFAULT_REMINDER_MINUTES = 15
  PROVIDER_LOCATIONS = Crm::BookingPageSettings::CALENDAR_LOCATIONS
  # Textos de consentimento que a página pode mostrar. Outro valor não é consentimento: é ignorado.
  CONSENT_TEXT_KEYS = %w[booking_v2.consent.whatsapp_notices].freeze

  # Funil e etapa em que a reserva cai: os da página ou, sem eles, o primeiro funil ativo e a primeira etapa dele.
  # Também usado pelo publicar, que recusa página sem destino.
  def self.pipeline_target(profile)
    pipelines = profile.account.crm_pipelines
    pipeline = profile.default_pipeline_id ? pipelines.find_by(id: profile.default_pipeline_id) : pipelines.active.order(:id).first
    stage_id = profile.default_stage_id.presence || pipeline&.stages&.order(:position)&.first&.id
    { pipeline_id: pipeline&.id, stage_id: stage_id }
  end

  # Interface pedida pelo plano (#1188): um argumento nomeado por dado do formulário.
  def initialize(profile:, name:, phone:, starts_at:, source:, email: nil, duration: nil, location_type: nil, # rubocop:disable Metrics/ParameterLists
                 consent: {}, conversation: nil, link: nil)
    @profile = profile
    @account = profile.account
    @input = Crm::BookingV2::BookingInput.new(profile: profile, name: name, phone: phone, starts_at: starts_at, email: email,
                                              duration: duration, location_type: location_type)
    @source = source.to_s
    @consent = consent.to_h.with_indifferent_access
    @conversation = conversation
    @link = link if link.present? && link.booking_profile_id == profile.id && link.enabled?
  end

  def perform
    validate_inputs!
    previous = existing_result
    return previous if previous

    ensure_slot_available!(include_provider: true)
    result = ActiveRecord::Base.transaction do
      acquire_locks!
      existing_result || book!
    end
    broadcast_card_created(result.card) unless result.existing
    result
  end

  private

  attr_reader :profile, :account, :input

  delegate :name, :phone, :phone_candidates, :email, :starts_at, :duration_minutes, :location, to: :input

  def host
    @host ||= @link&.agent || profile.default_assignee
  end

  def validate_inputs!
    input.validate!
    raise ArgumentError, 'host_unavailable' unless Crm::BookingV2::HostEligibility.eligible?(account: account, user: host)

    validate_provider_location!
  end

  # Meet/Teams: o convite sai pelo provedor, então precisa de e-mail do cliente e da caixa da página com agenda.
  def validate_provider_location!
    return unless provider_location?
    raise ArgumentError, 'email_required' if email.blank?

    channel = profile.inbox&.channel
    connected = channel.is_a?(Channel::Email) && channel.calendar_enabled? && channel.public_send(PROVIDER_LOCATIONS[location['type']])
    raise ArgumentError, 'calendar_unavailable' unless connected
  end

  def provider_location?
    PROVIDER_LOCATIONS.key?(location['type'])
  end

  def acquire_locks!
    connection = ActiveRecord::Base.connection
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_INBOX}, #{profile.inbox_id.to_i})") if profile.inbox_id.present?
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_AGENT}, #{host.id.to_i})")
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_PHONE}, #{phone_lock_key})")
  end

  # O lock de dois argumentos recebe int4 com sinal: o crc32 (0..2^32-1) é levado para -2^31..2^31-1.
  def phone_lock_key
    crc = Zlib.crc32("#{account.id}:#{phone}")
    crc > INT32_MAX ? crc - INT32_RANGE : crc
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

    ensure_slot_available!(include_provider: false)
    contact = find_or_create_contact!
    card = create_card!(contact)
    meeting = create_meeting!(card)
    Result.new(meeting: meeting, contact: contact, card: card, existing: false)
  end

  def ensure_slot_available!(include_provider:)
    local_date = starts_at.in_time_zone(profile.resolved_timezone).to_date.iso8601
    available = Crm::BookingV2::Slots.new(profile: profile, host: host, date: local_date, duration: duration_minutes, strict: true,
                                          include_provider: include_provider).perform
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

  # Interna: os metadados vão como chaves soltas (contrato do InternalCreator). Meet/Teams: o Creator grava origem e
  # metadados da página já no rascunho, antes de chamar o provedor.
  def create_meeting!(card)
    params = meeting_params(card)
    unless provider_location?
      return Crm::Meetings::InternalCreator.new(**creator_args, card: card, params: params.merge(booking_metadata.symbolize_keys)).perform
    end

    Crm::Meetings::Creator.new(**creator_args, card: card, params: params.except(:location_type).merge(booking_metadata: booking_metadata)).perform
  end

  def creator_args
    { account: account, inbox: profile.inbox, scheduled_by: host }
  end

  def meeting_params(card)
    {
      title: profile.title.presence || card.title, description: profile.description,
      starts_at: starts_at, ends_at: starts_at + duration_minutes.minutes, timezone: profile.resolved_timezone,
      reminder_minutes_before: DEFAULT_REMINDER_MINUTES, extra_guests: extra_guests(card),
      guest_phone: phone, source: @source.presence
    }.merge(location_params)
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
    consent = consent_metadata
    consent ? data.merge('consent' => consent) : data
  end

  # Data e hora do consentimento são do servidor; o texto só vale se for um dos que a página mostra.
  def consent_metadata
    text_key = @consent[:text_key].to_s
    return unless CONSENT_TEXT_KEYS.include?(text_key)

    { 'accepted_at' => Time.current.iso8601, 'text_key' => text_key }
  end

  def pipeline_target
    @pipeline_target ||= self.class.pipeline_target(profile)
  end

  def pipeline_id
    pipeline_target[:pipeline_id] || (raise ArgumentError, 'no_pipeline_configured')
  end

  def stage_id
    pipeline_target[:stage_id] || (raise ArgumentError, 'no_stage_configured')
  end

  # Depois do commit: o card novo aparece no Kanban e no calendário de quem está aberto (como no v1). A reserva já
  # está feita; falha aqui só é registrada.
  def broadcast_card_created(card)
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_CREATED)
  rescue StandardError => e
    Rails.logger.error("CRM booking v2 realtime broadcast failed: #{e.class.name}")
  end
end
