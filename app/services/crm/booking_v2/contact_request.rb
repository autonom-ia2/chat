# "Nenhum horário serve?" da página pública v2 (#1189, J2-A10): quem não achou horário deixa nome e WhatsApp e
# vira trabalho para o responsável. Acha o contato pelo telefone (sem renomear o que o atendimento já tem) ou cria,
# cria um card no funil e etapa da página (`source: 'contact_request'`, dono = responsável), uma tarefa de ligação
# vencendo agora para o responsável e a atividade no card.
#
# Limite: no máximo 2 pedidos abertos (tarefa pendente ou atrasada) por telefone nas últimas 24 horas. Feito sob a
# mesma trava de telefone do `Booker` (`pg_advisory_xact_lock(4, ...)`), para dois envios simultâneos não passarem
# do limite nem criarem dois contatos.
#
# Vindo do link do cliente (`invite_code`): o convite precisa ser desta página e estar ativo. Nome e telefone vêm do
# contato do convite quando a pessoa não digitou (o cliente não preenche de novo); o contato é o do convite (nada de
# contato duplicado) e o card aberto do convite é reaproveitado. Convite que não serve: 'booking_failed'.
#
# Erros: ArgumentError 'invalid_name', 'invalid_phone', 'too_many_open', 'host_unavailable',
# 'no_pipeline_configured', 'no_stage_configured', 'booking_failed'.
class Crm::BookingV2::ContactRequest
  SOURCE = 'contact_request'.freeze
  FOLLOW_UP_SOURCE = 'booking_contact_request'.freeze
  ACTIVITY = 'booking_contact_requested'.freeze
  MAX_OPEN_PER_DAY = 2
  LOCK_NS_PHONE = Crm::BookingV2::Booker::LOCK_NS_PHONE
  INT32_RANGE = 2**32
  INT32_MAX = (2**31) - 1

  def initialize(page:, name:, phone:, consent: {}, invite_code: nil)
    @page = page
    @invite_code = invite_code.to_s
    contact = invite&.contact
    @input = Crm::BookingV2::BookingInput.new(profile: page.profile, name: name.presence || contact&.name,
                                              phone: phone.presence || contact&.phone_number, starts_at: nil)
    @consent = consent.to_h.with_indifferent_access
  end

  def perform
    validate!
    card = ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_PHONE}, #{phone_lock_key})")
      raise ArgumentError, 'too_many_open' if open_requests >= MAX_OPEN_PER_DAY

      create_request!
    end
    broadcast_card_created(card) unless invite_card
    card
  end

  private

  attr_reader :page, :input

  delegate :profile, :account, :host, to: :page
  delegate :name, :phone, :phone_candidates, to: :input

  def invite
    return if @invite_code.blank?

    @invite ||= Crm::BookingInvite.includes(:contact, :card).find_by(code: @invite_code)
  end

  def validate!
    raise ArgumentError, 'booking_failed' if @invite_code.present? && !usable_invite?
    raise ArgumentError, 'invalid_name' if name.blank?
    raise ArgumentError, 'invalid_phone' if phone.blank?
    raise ArgumentError, 'host_unavailable' unless Crm::BookingV2::HostEligibility.eligible?(account: account, user: host)
  end

  def usable_invite?
    Crm::BookingV2::PublicBooking.invite_for_page?(invite, page) && invite.active?
  end

  # Mesma chave do Booker: crc32("conta:telefone") levado para int4 com sinal.
  def phone_lock_key
    crc = Zlib.crc32("#{account.id}:#{phone}")
    crc > INT32_MAX ? crc - INT32_RANGE : crc
  end

  def open_requests
    Crm::FollowUp.active.where(account_id: account.id, follow_up_type: :call)
                 .where("crm_follow_ups.metadata->>'source' = ?", FOLLOW_UP_SOURCE)
                 .where(contact_id: account.contacts.where(phone_number: phone_candidates).select(:id))
                 .where('crm_follow_ups.created_at > ?', 24.hours.ago).count
  end

  def create_request!
    contact = invite&.contact || Crm::BookingV2::PhoneLookup.find_contact(account: account, e164: phone) ||
              account.contacts.create!(name: name, phone_number: phone)
    card = invite_card || create_card!(contact)
    follow_up = create_follow_up!(card, contact)
    Crm::FollowUps::CardNextDueUpdater.update(card)
    Crm::ActivityLogger.new(card: card, actor: nil, event_type: ACTIVITY,
                            payload: { booking_profile_id: profile.id, follow_up_id: follow_up.id }).perform
    card
  end

  def invite_card
    card = invite&.card
    card if card&.open?
  end

  def create_card!(contact)
    target = Crm::BookingV2::Booker.pipeline_target(profile)
    Crm::Cards::Creator.new(
      account: account, user: nil,
      params: {
        pipeline_id: target[:pipeline_id] || (raise ArgumentError, 'no_pipeline_configured'),
        stage_id: target[:stage_id] || (raise ArgumentError, 'no_stage_configured'),
        contact_id: contact.id, owner_id: host.id, currency: 'BRL', source: SOURCE,
        title: "#{contact.name.presence || name} - #{profile.title.presence || 'Agendamento'}".first(255)
      }
    ).perform
  end

  def create_follow_up!(card, contact)
    Crm::FollowUp.create!(
      account: account, card: card, contact: contact, assignee: host, created_by: nil,
      title: follow_up_title(contact), due_at: Time.current, timezone: profile.resolved_timezone,
      follow_up_type: :call, automation_mode: :reminder_only, status: :pending,
      metadata: { 'source' => FOLLOW_UP_SOURCE, 'booking_profile_id' => profile.id, 'consent' => consent_metadata }.compact
    )
  end

  def follow_up_title(contact)
    I18n.t('crm.booking_v2.contact_request.follow_up_title', name: contact.name.presence || name,
                                                             locale: Crm::BookingV2::LocationLabel.locale(account)).first(255)
  end

  # Mesma regra do Booker: hora do servidor e só um texto que a página mostra.
  def consent_metadata
    text_key = @consent[:text_key].to_s
    return unless ActiveModel::Type::Boolean.new.cast(@consent[:accepted])
    return unless Crm::BookingV2::Booker::CONSENT_TEXT_KEYS.include?(text_key)

    { 'accepted_at' => Time.current.iso8601, 'text_key' => text_key }
  end

  def broadcast_card_created(card)
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_CREATED)
  rescue StandardError => e
    Rails.logger.error("CRM booking v2 contact request broadcast failed: #{e.class.name}")
  end
end
