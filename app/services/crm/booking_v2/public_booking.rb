# Reserva feita pela página pública v2 (#1189): pelo link público ou pelo link por cliente (`invite_code`).
#
# Sem transação própria: a do `Booker` é a única. A consulta ao provedor (freebusy) roda antes dela e o aviso em tempo
# real sai depois do commit. O que precisa nascer junto com a reunião é gravado no bloco do `Booker`, dentro da
# transação e sob as travas dele.
#
# Link público: `Booker` com `source: 'public_link'` e, no bloco, um convite `channel: 'public'` com contato, card e
# reunião, que vira o link de gestão (`/b/<code>`): um único mecanismo de acesso à reunião.
#
# Convite: conferido sem trava antes do `Booker` (recusa cedo, sem consultar o provedor) e de novo no bloco, com a
# linha travada (`SELECT ... FOR UPDATE`): ativo, ainda sem reunião e com a reunião nova sendo do contato do convite.
# Dois pedidos do mesmo convite ao mesmo tempo: o segundo encontra o convite já agendado e a transação dele desfaz a
# reunião. Contato, card e conversa vêm do convite. O telefone é o do contato; se o cliente trocou o número ("Mudar o
# número") ou o contato não tem, vale o digitado, só para esta reunião (o contato não muda). `source: 'invite'`.
#
# Reenvio (duplo toque, rede que repete): só com o mesmo `request_id` (16 a 64 letras, dígitos, `-` ou `_`, sorteado
# pelo navegador por tentativa), gravado na reunião e no convite. Mesma chave devolve a mesma reserva; sem chave ou
# com outra, a reunião que já existe ocupa o horário (`slot_unavailable`) e nenhum dado dela sai. Nunca se cria
# convite público para reunião que não nasceu deste pedido.
#
# Erros: ArgumentError com o código do `Booker`, ou 'booking_failed' para convite que não serve ou `request_id` fora
# do formato. O controller reduz ao conjunto público.
class Crm::BookingV2::PublicBooking
  Outcome = Struct.new(:meeting, :invite, :existing, keyword_init: true)
  REQUEST_ID_LENGTH = (16..64)
  REQUEST_ID_CHARS = Set.new([*'a'..'z', *'A'..'Z', *'0'..'9', '-', '_']).freeze

  def self.valid_request_id?(value)
    REQUEST_ID_LENGTH.cover?(value.length) && value.each_char.all? { |char| REQUEST_ID_CHARS.include?(char) }
  end

  # O convite é desta página (conta, página e, se tiver, o link individual) e não foi cancelado. Também usado pelo
  # pedido de contato vindo do convite (`ContactRequest`).
  def self.invite_for_page?(invite, page)
    return false if invite.blank? || invite.canceled_at.present?
    return false unless invite.account_id == page.account.id && invite.booking_profile_id == page.profile.id

    invite.booking_link_id.nil? || invite.booking_link_id == page.link&.id
  end

  def initialize(page:, params:)
    @page = page
    @params = params.to_h.with_indifferent_access
    @request_id = @params[:request_id].to_s.presence
  end

  def perform
    raise ArgumentError, 'booking_failed' if request_id && !self.class.valid_request_id?(request_id)

    invite_code.present? ? book_with_invite : book_public
  end

  private

  attr_reader :page, :params, :request_id

  def profile
    page.profile
  end

  def invite_code
    params[:invite_code].to_s
  end

  def book_public
    created = nil
    result = booker(phone: params[:phone], source: 'public_link', link: page.link).perform do |booked|
      created = create_public_invite!(booked)
    end
    Outcome.new(meeting: result.meeting, invite: created || repeated_public_invite(result.meeting), existing: result.existing)
  end

  def create_public_invite!(result)
    Crm::BookingInvite.create!(
      account: page.account, booking_profile: profile, booking_link: page.link, contact: result.contact, card: result.card,
      meeting: result.meeting, channel: 'public', scheduled_at: Time.current,
      expires_at: result.meeting.ends_at + Crm::BookingInvite::MANAGE_GRACE, metadata: { 'request_id' => request_id }.compact
    )
  end

  # Reenvio com a mesma chave: o convite público que nasceu com ela. Outro convite não é devolvido.
  def repeated_public_invite(meeting)
    Crm::BookingInvite.where(meeting_id: meeting.id, channel: 'public').where("metadata->>'request_id' = ?", request_id).first ||
      raise(ArgumentError, 'slot_unavailable')
  end

  def book_with_invite
    invite = Crm::BookingInvite.find_by(code: invite_code)
    raise ArgumentError, 'booking_failed' unless self.class.invite_for_page?(invite, page)
    return repeated_invite_booking(invite) if invite.scheduled_at.present?
    raise ArgumentError, 'booking_failed' unless invite.active?

    result = invite_booker(invite).perform { |booked| attach_meeting!(invite, booked.meeting) }
    return repeated_invite_booking(invite.reload) if result.existing

    Outcome.new(meeting: result.meeting, invite: invite, existing: false)
  end

  # Dentro da transação do `Booker`: trava o convite e confere de novo. Qualquer recusa desfaz a reunião.
  def attach_meeting!(invite, meeting)
    invite.lock!
    usable = invite.scheduled_at.nil? && invite.active? && meeting.card.contact_id == invite.contact_id
    raise ArgumentError, 'booking_failed' unless usable

    invite.update!(scheduled_at: Time.current, meeting: meeting, metadata: invite.metadata.to_h.merge('request_id' => request_id).compact)
  end

  def invite_booker(invite)
    booker(phone: params[:phone].presence || invite.contact.phone_number, source: 'invite', link: invite.booking_link || page.link,
           contact: invite.contact, card: invite.card, conversation: invite.conversation)
  end

  # Convite já agendado: só o reenvio da mesma reserva (mesma chave, mesma hora, há pouco) responde de novo.
  def repeated_invite_booking(invite)
    meeting = invite.meeting
    repeated = request_id.present? && invite.metadata.to_h['request_id'] == request_id && meeting.present? && meeting.scheduled? &&
               meeting.starts_at == requested_start && invite.scheduled_at > Crm::BookingV2::Booker::IDEMPOTENCY_WINDOW.ago
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
      source: source, link: link, idempotency_key: request_id, **extra
    )
  end

  # Só há consentimento quando a pessoa marcou e o texto é um dos que a página mostra (o Booker confere de novo).
  def consent
    data = params[:consent].to_h.with_indifferent_access
    return {} unless ActiveModel::Type::Boolean.new.cast(data[:accepted])

    { text_key: data[:text_key].to_s }
  end
end
