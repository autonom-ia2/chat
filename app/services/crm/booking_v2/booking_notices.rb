# Os avisos de uma reserva que acabou de ser gravada (#1305): o PONTO ÚNICO pelo qual a página pública
# (`Public::Api::V2::BookingController`), o painel (`PanelBooking`) e a IA (`Native::AgendarReuniao`) agendam o aviso
# "ao marcar", os lembretes e o link de gestão que eles levam (`Notices::Scheduler#schedule!`). Antes a página e o
# painel copiavam a chamada e a IA não a fazia: a reunião marcada pela IA não avisava nem lembrava o cliente.
#
# Roda DEPOIS do commit da reserva; repetir não duplica (o Scheduler é único por reunião e aviso). Erro aqui não
# desfaz a reunião: vai ao rastreador e ao log, e `schedule` responde que o aviso não vai sair.
#
# `told_in`: a conversa em que o cliente já ouviu a confirmação (a da IA). Quando ela é da MESMA caixa de avisos da
# página, o aviso "ao marcar" cairia na mesma conversa logo depois da resposta da IA, repetindo o que ela acabou de
# dizer: ele nasce pulado (`told_in_conversation`) e os lembretes seguem. Em outra caixa (IA no Instagram, avisos no
# WhatsApp) o aviso sai: é o canal dos avisos e leva o "Parar avisos".
class Crm::BookingV2::BookingNotices
  TOLD_IN_CONVERSATION = 'told_in_conversation'.freeze
  BOOKED = 'booked'.freeze

  def initialize(meeting:, invite:, told_in: nil)
    @meeting = meeting
    @invite = invite
    @told_in = told_in
  end

  # -> true quando o aviso "ao marcar" vai de fato sair (a tela de sucesso só promete mensagem assim, J2-A6).
  def schedule
    Crm::BookingV2::Notices::Scheduler.new(meeting).schedule!(invite: invite, skip: skipped_kinds)
    notice = meeting.notices.find_by(kind: BOOKED)
    notice.present? && notice.pending? && Crm::BookingV2::Notices::Sender.new(notice).will_send?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: meeting.account).capture_exception
    Rails.logger.error("Booking v2 notices not scheduled: meeting=#{meeting.id} source=#{meeting.source} #{e.class.name}")
    false
  end

  private

  attr_reader :meeting, :invite, :told_in

  def skipped_kinds
    told_in_notice_inbox? ? { BOOKED => TOLD_IN_CONVERSATION } : {}
  end

  def told_in_notice_inbox?
    profile = Crm::BookingV2::Notices::Scheduler.profile_for(meeting)
    told_in.present? && profile&.notice_inbox_id.present? && told_in.inbox_id == profile.notice_inbox_id
  end
end
