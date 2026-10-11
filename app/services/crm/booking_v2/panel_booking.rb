# Reunião marcada pela atendente no painel (#1265): "+ Novo › Reunião" e "Agendar reunião" do card, pela agenda de
# uma página nova publicada, sem caixa Google/Microsoft.
#
# Mesmo `Crm::BookingV2::Booker` da página pública e da IA: mesmas travas, mesma regra de horário (feriados, Meus
# horários, intervalos, antecedência), mesmo card do contato. `source: 'panel'` marca a reunião (e o card, se nascer
# agora) como marcada pela equipe; `metadata.booked_by_user_id` guarda quem marcou (o responsável da reunião continua
# sendo o da página, como em toda reserva).
#
# Cliente: o contato do card (ou o contato pedido), com o telefone dele normalizado pela biblioteca de telefone. Sem
# telefone válido não há reserva (`invalid_phone`): o aviso e o link de gestão vão pelo WhatsApp. O card pedido
# recebe a reunião (o Booker confere que é desse contato); card fechado é recusado (`card_closed`), para a reunião
# não cair em outro card. Só com o contato, o Booker usa o card aberto dele no funil da página ou cria um.
#
# Responsável: página `per_agent` usa o link de quem marca; se ela não atende ali, o primeiro link ativo (a mesma
# regra do convite, `InvitePages#link_for`).
#
# Junto com a reunião, no bloco do Booker (mesma transação, sob as travas), nasce o convite `channel: 'panel'`: o link
# de gestão que os avisos levam. Avisos no WhatsApp só com `notify` e página com caixa de avisos, agendados depois do
# commit, como na página pública. Sem `notify`, a reunião guarda `notify_client: false` e o `Notices::Scheduler` não
# agenda aviso nenhum, nem ao remarcar. Com `notify`, a reunião guarda `notice_basis: 'combinado_com_atendente'`
# (#1271: o motivo de avisar quem não marcou sozinho) e o aviso "ao marcar" diz quem marcou (`Notices::Text`).
#
# Reenvio: `request_id` (16 a 64 letras, dígitos, `-` ou `_`, sorteado pelo navegador por tentativa) devolve a mesma
# reunião. Erros: ArgumentError com o código do Booker, ou `no_contact`/`booking_failed`.
class Crm::BookingV2::PanelBooking
  SOURCE = 'panel'.freeze
  CHANNEL = 'panel'.freeze
  NOTICE_BASIS = 'combinado_com_atendente'.freeze
  Outcome = Struct.new(:meeting, :invite, :existing, :notice_will_send, keyword_init: true)

  # `client`: { card:, contact: } já autorizados pelo controller.
  def initialize(page:, user:, client:, params:)
    @page = page
    @user = user
    @card = client[:card]
    @contact = @card&.contact || client[:contact]
    @params = params.to_h.with_indifferent_access
  end

  def perform
    validate_request!
    created = nil
    result = booker.perform { |booked| created = record_booking!(booked) }
    invite = created || Crm::BookingInvite.where(meeting_id: result.meeting.id, channel: CHANNEL).order(:id).last
    notice_will_send = result.existing ? false : schedule_notices(result.meeting, invite)
    Outcome.new(meeting: result.meeting, invite: invite, existing: result.existing, notice_will_send: notice_will_send)
  end

  private

  attr_reader :page, :user, :card, :contact, :params

  def validate_request!
    validate_client!
    raise ArgumentError, 'booking_failed' if request_id && !Crm::BookingV2::PublicBooking.valid_request_id?(request_id)
    raise ArgumentError, 'invalid_phone' if phone.blank?
  end

  def validate_client!
    raise ArgumentError, 'no_contact' if contact.blank? || contact.account_id != page.account_id
    raise ArgumentError, 'card_closed' if card.present? && !card.open?
  end

  def request_id
    params[:request_id].to_s.presence
  end

  def phone
    @phone ||= Crm::BookingV2::PhoneLookup.normalize(contact.phone_number,
                                                     region: Crm::BookingV2::PhoneLookup.region_for(page.resolved_timezone))
  end

  def link
    @link ||= Crm::BookingV2::InvitePages.new(page.account).link_for(page, user)
  end

  def booker
    Crm::BookingV2::Booker.new(
      profile: page, name: contact.name.presence || phone, phone: phone, email: email, starts_at: params[:starts_at],
      duration: params[:duration].presence, location_type: params[:location].presence, source: SOURCE, link: link,
      contact: contact, card: card, conversation: card&.primary_conversation,
      idempotency_key: request_id && "panel:#{user.id}:#{request_id}"
    )
  end

  # Meet/Teams mandam convite por e-mail: vai o do contato (o Booker recusa com `email_required` sem ele).
  def email
    contact.email.presence
  end

  # Dentro da transação do Booker, só para a reserva nova: quem marcou, se avisa o cliente e o link de gestão.
  def record_booking!(booked)
    meeting = booked.meeting
    meeting.update!(metadata: meeting.metadata.to_h.merge(booking_metadata))
    Crm::BookingInvite.create!(
      account: page.account, booking_profile: page, booking_link: link, contact: booked.contact, card: booked.card,
      conversation: invite_conversation(booked), meeting: meeting, created_by: user, channel: CHANNEL,
      scheduled_at: Time.current, expires_at: meeting.ends_at + Crm::BookingInvite::MANAGE_GRACE
    )
  end

  # Com aviso, fica registrado o motivo de mandar mensagem a quem não marcou sozinho (#1271): a atendente declarou,
  # ao ligar "Avisar o cliente no WhatsApp", que o horário foi combinado com o cliente.
  def booking_metadata
    data = { 'booked_by_user_id' => user.id, 'notify_client' => notify? }
    notify? ? data.merge('notice_basis' => NOTICE_BASIS) : data
  end

  def invite_conversation(booked)
    conversation = booked.card.primary_conversation
    conversation if conversation&.contact_id == booked.contact.id
  end

  def notify?
    ActiveModel::Type::Boolean.new.cast(params[:notify]) == true
  end

  # Igual à página pública: agenda depois da reserva gravada; erro aqui não desfaz a reunião, só não promete mensagem.
  def schedule_notices(meeting, invite)
    return false unless notify?

    Crm::BookingV2::Notices::Scheduler.new(meeting).schedule!(invite: invite)
    notice = meeting.notices.find_by(kind: 'booked')
    notice.present? && notice.pending? && Crm::BookingV2::Notices::Sender.new(notice).will_send?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: page.account).capture_exception
    Rails.logger.error("Panel booking notices not scheduled: #{e.class.name}")
    false
  end
end
