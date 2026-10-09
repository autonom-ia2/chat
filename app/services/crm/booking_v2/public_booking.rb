# Reserva feita pela página pública v2 (#1189): pelo link público ou pelo link por cliente (`invite_code`).
#
# Link público: `Booker` com `source: 'public_link'` e, na mesma transação, um convite `channel: 'public'` com
# contato, card e reunião, que vira o link de gestão (`/b/<code>`): um único mecanismo de acesso à reunião.
#
# Convite: a linha do convite é travada (`SELECT ... FOR UPDATE`) antes do `Booker`. O convite precisa estar ativo,
# ser desta página (e, se tem link individual, deste link) e ainda não ter virado reunião. Contato, card e conversa
# vêm do convite. O telefone é o do contato; se o cliente trocou o número ("Mudar o número") ou o contato não tem,
# vale o digitado, só para esta reunião (o contato não muda). `source: 'invite'`.
# Depois da reserva o convite guarda `scheduled_at` e `meeting`; convite de teste marca a reunião com `test: true`.
#
# Reenvio (duplo toque, rede que repete): o `Booker` devolve a reunião existente; aqui devolvemos o mesmo convite,
# e o convite já agendado com a mesma hora há menos de 5 minutos responde a mesma reserva.
#
# Erros: ArgumentError com o código do `Booker`, ou 'booking_failed' para convite que não serve. O controller
# reduz ao conjunto público.
class Crm::BookingV2::PublicBooking
  Outcome = Struct.new(:meeting, :invite, :existing, keyword_init: true)

  def initialize(page:, params:)
    @page = page
    @params = params.to_h.with_indifferent_access
  end

  def perform
    ActiveRecord::Base.transaction { invite_code.present? ? book_with_invite : book_public }
  end

  private

  attr_reader :page, :params

  def profile
    page.profile
  end

  def invite_code
    params[:invite_code].to_s
  end

  def book_public
    result = booker(phone: params[:phone], source: 'public_link', link: page.link).perform
    invite = Crm::BookingInvite.find_by(meeting_id: result.meeting.id) if result.existing
    Outcome.new(meeting: result.meeting, invite: invite || create_public_invite!(result), existing: result.existing)
  end

  def create_public_invite!(result)
    Crm::BookingInvite.create!(
      account: page.account, booking_profile: profile, booking_link: page.link, contact: result.contact, card: result.card,
      meeting: result.meeting, channel: 'public', scheduled_at: Time.current,
      expires_at: result.meeting.ends_at + Crm::BookingInvite::MANAGE_GRACE
    )
  end

  def book_with_invite
    invite = Crm::BookingInvite.lock.find_by(code: invite_code)
    raise ArgumentError, 'booking_failed' unless invite_for_this_page?(invite)
    return repeated_invite_booking(invite) if invite.scheduled_at.present?
    raise ArgumentError, 'booking_failed' unless invite.active?

    result = invite_booker(invite).perform
    invite.update!(scheduled_at: Time.current, meeting: result.meeting)
    mark_test_meeting!(result.meeting) if invite.metadata.to_h['test'] == true
    Outcome.new(meeting: result.meeting, invite: invite, existing: result.existing)
  end

  # Reunião marcada por convite de "Testar no meu WhatsApp" (#1192): fica fora dos números (`Crm::Meeting.real`).
  def mark_test_meeting!(meeting)
    meeting.update!(metadata: meeting.metadata.to_h.merge('test' => true))
  end

  def invite_booker(invite)
    booker(phone: params[:phone].presence || invite.contact.phone_number, source: 'invite', link: invite.booking_link || page.link,
           contact: invite.contact, card: invite.card, conversation: invite.conversation)
  end

  def invite_for_this_page?(invite)
    return false if invite.blank? || invite.canceled_at.present?
    return false unless invite.account_id == page.account.id && invite.booking_profile_id == profile.id

    invite.booking_link_id.nil? || invite.booking_link_id == page.link&.id
  end

  # Convite já agendado: só o reenvio da mesma reserva (mesma hora, há pouco) responde de novo; o resto é recusado.
  def repeated_invite_booking(invite)
    meeting = invite.meeting
    repeated = meeting.present? && meeting.scheduled? && meeting.starts_at == requested_start &&
               invite.scheduled_at > Crm::BookingV2::Booker::IDEMPOTENCY_WINDOW.ago
    raise ArgumentError, 'booking_failed' unless repeated

    Outcome.new(meeting: meeting, invite: invite, existing: true)
  end

  def requested_start
    Time.iso8601(params[:starts_at].to_s)
  rescue ArgumentError
    nil
  end

  def booker(phone:, source:, link:, **extra)
    Crm::BookingV2::Booker.new(
      profile: profile, name: params[:name], phone: phone, email: params[:email], starts_at: params[:starts_at],
      duration: params[:duration].presence, location_type: params[:location_type].presence, consent: consent,
      source: source, link: link, **extra
    )
  end

  # Só há consentimento quando a pessoa marcou e o texto é um dos que a página mostra (o Booker confere de novo).
  def consent
    data = params[:consent].to_h.with_indifferent_access
    return {} unless ActiveModel::Type::Boolean.new.cast(data[:accepted])

    { text_key: data[:text_key].to_s }
  end
end
