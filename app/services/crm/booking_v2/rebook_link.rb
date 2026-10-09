# "Enviar link para marcar outro horário" (#1193, J4-A6): o cliente faltou e o agente, com um toque, manda na conversa
# o link do cliente para ele escolher outro horário. Mesmo caminho do botão Agendar (F1-C): `InviteCreator` e
# `InviteDeliverer`, com as mesmas regras (o convite é da página da reunião, se ainda atende; senão a página em que a
# pessoa atende; janela de mensagens do canal).
#
# Recusa (MeetingActionError):
# - `not_rebookable`: a reunião não foi marcada como "Cliente faltou" ou não veio de uma página de agendamento;
# - `stopped`: o cliente recusou mensagens ativas ou parou os avisos (contato ou reunião) — nada é criado nem sai;
# - `recently_sent`: o link já saiu há menos de 10 minutos (dois toques, ou a tela reaberta) — nada é criado;
# - `no_conversation` e `cannot_reply`: o convite é criado e o link vai em `url` para o agente copiar.
# Recusas do convite (`no_page`, `invite_invalid`) sobem como `InviteError`.
#
# A trava na reunião faz o segundo de dois toques simultâneos ver o envio do primeiro.
class Crm::BookingV2::RebookLink
  COOLDOWN = Crm::BookingV2::MeetingReminder::COOLDOWN

  def initialize(meeting:, user:, client:)
    @meeting = meeting
    @user = user
    @client = client
  end

  def perform
    refuse!('not_rebookable') unless meeting.booking? && meeting.outcome_no_show?
    refuse!('stopped') if client.stopped?

    refusal = nil
    invite = ActiveRecord::Base.transaction do
      meeting.lock!
      refuse!('recently_sent') if recently_sent?
      created, refusal = create_and_deliver
      created
    end
    raise refusal if refusal

    invite
  end

  private

  attr_reader :meeting, :user, :client

  # [convite, recusa ou nil]. A recusa sobe depois da transação, para o convite ficar e o agente poder copiar o link.
  def create_and_deliver
    conversation = client.reply_conversation
    invite = create_invite(conversation)
    return [invite, Crm::BookingV2::MeetingActionError.new('no_conversation', url: invite.url)] if conversation.blank?

    [invite, deliver(invite, conversation)]
  end

  def create_invite(conversation)
    Crm::BookingV2::InviteCreator.new(
      account: meeting.account, user: user, page_id: page_id,
      client: { card: meeting.card, conversation: conversation, contact: client.contact }
    ).perform
  end

  # A página da reunião, se ainda recebe convite; senão nenhuma (o `InviteCreator` escolhe a da pessoa).
  def page_id
    id = meeting.metadata.to_h['booking_profile_id']
    Crm::BookingV2::InvitePages.new(meeting.account).usable.find { |page| page.id == id.to_i }&.id
  end

  def recently_sent?
    last = meeting.metadata.to_h['rebook_link_sent_at']
    last.present? && Time.zone.parse(last.to_s).to_i > COOLDOWN.ago.to_i
  end

  # nil quando saiu; a recusa `cannot_reply` (com o link) quando o canal não deixa responder agora.
  def deliver(invite, conversation)
    message = Crm::BookingV2::InviteDeliverer.new(invite: invite, user: user, conversation: conversation).perform
    record!(invite, conversation, message)
    nil
  rescue Crm::BookingV2::InviteError => e
    raise unless e.message == 'cannot_reply'

    Crm::BookingV2::MeetingActionError.new('cannot_reply', url: invite.url)
  end

  def record!(invite, conversation, message)
    meeting.update!(metadata: meeting.metadata.to_h.merge('rebook_link_sent_at' => Time.current.iso8601, 'rebook_link_sent_by_id' => user.id))
    Crm::ActivityLogger.new(
      card: meeting.card, actor: user, event_type: 'booking_rebook_link_sent', conversation: conversation,
      payload: { meeting_id: meeting.id, starts_at: meeting.starts_at.iso8601, invite_id: invite.id, message_id: message.id }
    ).perform
  end

  def refuse!(code)
    raise Crm::BookingV2::MeetingActionError, code
  end
end
