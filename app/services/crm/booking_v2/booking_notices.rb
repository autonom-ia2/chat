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
# CONFIRMATION_GRACE depois e é pulado (`told_in_conversation`, sem chamar o responsável) quando a conversa recebeu a
# confirmação DESTA reunião: mensagem de saída pública, depois da reserva, que leva o link de gestão dela (`/b/<código>`,
# texto nosso, por comparação de texto). Decide em dois momentos: quando a mensagem é gravada (`mark_told!`, pelo
# `Crm::BookingNoticeToldListener`) e, como reserva, no envio (`Notices::Sender` → `already_told?`). Resposta de pessoa
# da equipe, aviso de outra reunião ou fala do bot sem o link não contam: aí o aviso sai, com o link. Se o turno
# morreu antes de responder, também. Os lembretes seguem normais. Em outra caixa (IA no Instagram, avisos no WhatsApp),
# o aviso sai na hora: é o canal dos avisos e leva o "Parar avisos".
class Crm::BookingV2::BookingNotices
  TOLD_IN_CONVERSATION = 'told_in_conversation'.freeze
  BOOKED = 'booked'.freeze
  # Folga para a resposta da IA chegar à conversa antes de decidir o "ao marcar" (o turno tem teto de 120 s).
  CONFIRMATION_GRACE = 5.minutes

  # No envio: o "ao marcar" de reunião que a IA confirmou na conversa da caixa de avisos, com o link dela lá.
  def self.already_told?(notice)
    return false unless notice.kind == BOOKED

    meeting = notice.meeting
    conversation = told_conversation(meeting)
    return false if conversation.nil? || !same_notice_inbox?(meeting, conversation)

    link = manage_url(meeting)
    link.present? && confirmations(conversation, meeting).any? { |message| message.content.to_s.include?(link) }
  end

  # Ao gravar a mensagem de saída: pula o "ao marcar" ainda pendente das reuniões desta conversa que ela confirma.
  # Só o que ainda está `pending`: o que o cron já tomou (`sending`) segue pela conferência do envio.
  def self.mark_told!(message)
    return unless confirmation?(message)

    pending_booked(message).find_each do |notice|
      next unless already_told?(notice)

      Crm::MeetingNotice.where(id: notice.id, status: :pending)
                        .update_all(status: Crm::MeetingNotice.statuses[:skipped], skip_reason: TOLD_IN_CONVERSATION, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def self.same_notice_inbox?(meeting, conversation)
    profile = Crm::BookingV2::Notices::Scheduler.profile_for(meeting)
    profile&.notice_inbox_id.present? && conversation.inbox_id == profile.notice_inbox_id
  end

  # Mensagem que pode ser a confirmação: de saída, pública, com texto e que não é um aviso nosso.
  def self.confirmation?(message)
    message.outgoing? && !message.private? && message.content.present? && message.content_attributes.to_h['crm_booking_notice'].blank?
  end

  def self.told_conversation(meeting)
    id = meeting.metadata.to_h['booked_in_conversation_id']
    id.present? ? Conversation.find_by(id: id, account_id: meeting.account_id) : nil
  end

  # O link de gestão da reunião: o convite do contato dela, nesta conta.
  def self.manage_url(meeting)
    Crm::BookingInvite.where(account_id: meeting.account_id, meeting_id: meeting.id, contact_id: meeting.card.contact_id, canceled_at: nil)
                      .order(:id).last&.url
  end

  def self.confirmations(conversation, meeting)
    conversation.messages.where(message_type: :outgoing, private: false).where('created_at >= ?', meeting.created_at)
                .select { |message| confirmation?(message) }
  end

  def self.pending_booked(message)
    Crm::MeetingNotice.pending.where(kind: BOOKED, account_id: message.account_id).joins(:meeting)
                      .where("crm_meetings.metadata->>'booked_in_conversation_id' = ?", message.conversation_id.to_s)
  end
  private_class_method :confirmation?, :told_conversation, :manage_url, :confirmations, :pending_booked

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
