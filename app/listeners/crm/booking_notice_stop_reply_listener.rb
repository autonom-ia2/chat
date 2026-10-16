# O cliente tocou em "Parar avisos" no modelo v2 do aviso (#1524): a resposta rápida chega como mensagem recebida com
# `content_attributes.selected_option.id == 'stop_notices'` (gravado pelo `RichMessages::SelectedOption`, #1511) e
# `in_reply_to` = a mensagem do aviso. Aqui os avisos do contato param, como no link de gestão
# (`Crm::BookingV2::ManageMeeting#stop_notices!`, motivo `whatsapp_button`).
#
# Só age quando dá para provar que é resposta a um aviso nosso, sem ler o texto (nada de lista de palavras):
# - mensagem recebida, com o id do botão, na conta com o agendamento ligado;
# - `in_reply_to` aponta uma mensagem da MESMA conversa marcada `crm_booking_notice` + `crm_booking_notice_id`
#   (a marca que o `Notices::Sender` põe no modelo v2); sem `in_reply_to`, nada;
# - o aviso e o convite são achados como no `Notices::Sender` (o convite mais recente da reunião), e o contato do
#   convite é o da conversa.
# Tocar de novo não repete o alerta ao responsável: o `stop_notices!` só alerta quando a parada é nova.
#
# Erro aqui não pode derrubar os outros ouvintes da mensagem: vai ao rastreador.
class Crm::BookingNoticeStopReplyListener < BaseListener
  STOP_ID = 'stop_notices'.freeze
  REASON = 'whatsapp_button'.freeze

  def message_created(event)
    message = event.data[:message]
    return unless stop_tap?(message)

    invite = invite_for(message)
    Crm::BookingV2::ManageMeeting.new(invite).stop_notices!(reason: REASON) if invite
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message&.account).capture_exception
  end

  private

  def stop_tap?(message)
    message&.incoming? && selected_id(message) == STOP_ID && Crm::Config.booking_v2_enabled?(message.account)
  end

  def selected_id(message)
    selected = attributes(message.content_attributes)[:selected_option]
    attributes(selected)[:id]
  end

  # `content_attributes` e o `selected_option` podem vir como hash (chave texto ou símbolo) ou como json em texto.
  def attributes(value)
    value = JSON.parse(value) if value.is_a?(String)
    value.is_a?(Hash) ? value.with_indifferent_access : {}
  rescue JSON::ParserError
    {}
  end

  def invite_for(message)
    notice = notice_for(message)
    return if notice.nil?

    invite = Crm::BookingInvite.where(meeting_id: notice.meeting_id).order(:id).last
    invite if invite && invite.contact_id == message.conversation.contact_id
  end

  def notice_for(message)
    replied_id = attributes(message.content_attributes)[:in_reply_to]
    return if replied_id.blank?

    replied = message.conversation.messages.find_by(id: replied_id)
    mark = attributes(replied&.content_attributes)
    return unless mark[:crm_booking_notice] && mark[:crm_booking_notice_id].present?

    Crm::MeetingNotice.find_by(id: mark[:crm_booking_notice_id], account_id: message.account_id)
  end
end
