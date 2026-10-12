# A IA confirmou a reunião na conversa (#1305): quando a mensagem de saída com o link de gestão é gravada, o aviso
# "ao marcar" ainda pendente daquela reunião vira `told_in_conversation` na hora, sem esperar o cron
# (`Crm::BookingV2::BookingNotices.mark_told!`). O envio confere de novo (`Notices::Sender`): se o cron tomar o aviso
# antes deste evento, a mensagem já gravada o faz pular do mesmo jeito.
#
# Erro aqui não pode derrubar os outros ouvintes da mensagem: vai ao rastreador e o envio decide.
class Crm::BookingNoticeToldListener < BaseListener
  def message_created(event)
    return unless Crm::Config.calendar_meetings_enabled?

    message = event.data[:message]
    return unless message&.outgoing?

    Crm::BookingV2::BookingNotices.mark_told!(message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message&.account).capture_exception
  end
end
