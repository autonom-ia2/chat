# Os avisos de uma reserva que acabou de ser gravada (#1305): o PONTO ÚNICO pelo qual a página pública
# (`Public::Api::V2::BookingController`), o painel (`PanelBooking`) e a IA (`Native::AgendarReuniao`) agendam o aviso
# "ao marcar", os lembretes e o link de gestão que eles levam (`Notices::Scheduler#schedule!`). Antes a página e o
# painel copiavam a chamada e a IA não a fazia: a reunião marcada pela IA não avisava nem lembrava o cliente.
#
# Roda DEPOIS do commit da reserva; repetir não duplica (o Scheduler é único por reunião e aviso). Erro aqui não
# desfaz a reunião: vai ao rastreador e ao log, e `schedule` responde que o aviso não vai sair.
#
# NÃO REPETIR A CONFIRMAÇÃO NA MESMA CONVERSA. `told_in` é a conversa em que a IA está confirmando a reunião. Quando
# ela é da MESMA caixa de avisos da página, o "ao marcar" cairia ali logo depois da resposta da IA. Então ele vence
# CONFIRMATION_GRACE depois, e no envio (`Notices::Sender`, por `already_told?`) só sai se a conversa NÃO recebeu
# mensagem de saída desde a reserva: com a resposta da IA lá, vira `told_in_conversation`; se o turno morreu antes de
# responder, o cliente recebe o aviso com o link. A decisão olha só dados (caixa, conversa, mensagens de saída e
# horários), nunca o texto. Os lembretes seguem normais. Em outra caixa (IA no Instagram, avisos no WhatsApp), o
# aviso sai na hora: é o canal dos avisos e leva o "Parar avisos".
class Crm::BookingV2::BookingNotices
  TOLD_IN_CONVERSATION = 'told_in_conversation'.freeze
  BOOKED = 'booked'.freeze
  # Folga para a resposta da IA chegar à conversa antes de decidir o "ao marcar" (o turno tem teto de 120 s).
  CONFIRMATION_GRACE = 5.minutes

  # O "ao marcar" de reunião que a IA confirmou na conversa da caixa de avisos, e a conversa já recebeu resposta
  # depois da reserva.
  def self.already_told?(notice)
    return false unless notice.kind == BOOKED

    meeting = notice.meeting
    conversation = told_conversation(meeting)
    return false if conversation.nil? || !same_notice_inbox?(meeting, conversation)

    conversation.messages.where(message_type: :outgoing, private: false).exists?(['created_at >= ?', meeting.created_at])
  end

  def self.told_conversation(meeting)
    id = meeting.metadata.to_h['booked_in_conversation_id']
    id.present? ? Conversation.find_by(id: id, account_id: meeting.account_id) : nil
  end

  def self.same_notice_inbox?(meeting, conversation)
    profile = Crm::BookingV2::Notices::Scheduler.profile_for(meeting)
    profile&.notice_inbox_id.present? && conversation.inbox_id == profile.notice_inbox_id
  end
  private_class_method :told_conversation

  def initialize(meeting:, invite:, told_in: nil)
    @meeting = meeting
    @invite = invite
    @told_in = told_in
  end

  # -> true quando o aviso "ao marcar" vai de fato sair (a tela de sucesso só promete mensagem assim, J2-A6).
  def schedule
    Crm::BookingV2::Notices::Scheduler.new(meeting).schedule!(invite: invite, defer: deferred_kinds)
    notice = meeting.notices.find_by(kind: BOOKED)
    notice.present? && notice.pending? && Crm::BookingV2::Notices::Sender.new(notice).will_send?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: meeting.account).capture_exception
    Rails.logger.error("Booking v2 notices not scheduled: meeting=#{meeting.id} source=#{meeting.source} #{e.class.name}")
    false
  end

  private

  attr_reader :meeting, :invite, :told_in

  def deferred_kinds
    told_in.present? && self.class.same_notice_inbox?(meeting, told_in) ? { BOOKED => CONFIRMATION_GRACE } : {}
  end
end
