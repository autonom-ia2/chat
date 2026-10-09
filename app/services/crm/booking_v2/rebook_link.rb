# "Enviar link para marcar outro horário" (#1193, J4-A6): o cliente faltou e o agente, com um toque, manda na conversa
# o link do cliente para ele escolher outro horário. Mesmo caminho do botão Agendar (F1-C): `InviteCreator` e
# `InviteDeliverer`, com as mesmas regras (o convite é da página da reunião, se ainda atende; senão a página em que a
# pessoa atende; janela de mensagens do canal).
#
# Recusa (MeetingActionError): `not_rebookable` (a reunião não foi marcada como "Cliente faltou" ou não veio de uma
# página de agendamento); `no_conversation` e `cannot_reply` (o convite é criado e o link vai em `url` para o agente
# copiar). Recusas do convite (`no_page`, `invite_invalid`) sobem como `InviteError`.
class Crm::BookingV2::RebookLink
  def initialize(meeting:, user:, client:)
    @meeting = meeting
    @user = user
    @client = client
  end

  def perform
    raise Crm::BookingV2::MeetingActionError, 'not_rebookable' unless meeting.booking? && meeting.outcome_no_show?

    conversation = client.reply_conversation
    invite = create_invite(conversation)
    raise Crm::BookingV2::MeetingActionError.new('no_conversation', url: invite.url) if conversation.blank?

    deliver!(invite, conversation)
    invite
  end

  private

  attr_reader :meeting, :user, :client

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

  def deliver!(invite, conversation)
    message = Crm::BookingV2::InviteDeliverer.new(invite: invite, user: user, conversation: conversation).perform
    Crm::ActivityLogger.new(
      card: meeting.card, actor: user, event_type: 'booking_rebook_link_sent', conversation: conversation,
      payload: { meeting_id: meeting.id, starts_at: meeting.starts_at.iso8601, invite_id: invite.id, message_id: message.id }
    ).perform
  rescue Crm::BookingV2::InviteError => e
    raise unless e.message == 'cannot_reply'

    raise Crm::BookingV2::MeetingActionError.new('cannot_reply', url: invite.url)
  end
end
