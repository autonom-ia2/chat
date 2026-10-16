# Apaga "para todos" no WhatsApp a mensagem apagada no painel (chat#1709, fase 3, WhatsappHybrid::RichNative::
# RevokeOnDelete), pela sessão do plano B. O motor (GOWS) exige o id serializado "true_<chatId>_<id físico>". A bolha já
# está apagada no painel: erro do motor (mensagem velha demais, sessão caída) vai só ao log, com a classe, e ao rastreador.
class WhatsappHybrid::RichNative::RevokeJob < ApplicationJob
  queue_as :medium

  def perform(message_id, physical_id)
    message = Message.find_by(id: message_id)
    connection = message && WhatsappHybrid::Connection.find_by(inbox_id: message.inbox_id)
    return if connection.nil? || physical_id.blank?

    client = Waha::Client.new
    chat_id = chat_id_for(connection, message, client)
    return if chat_id.blank?

    client.delete_message(session: connection.session_name, chat_id: chat_id, message_id: "true_#{chat_id}_#{physical_id}")
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] revoke failed message=#{message_id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: message&.account).capture_exception
  end

  private

  # O mesmo chat que o envio usa (cache do WebTransport; senão, a consulta ao motor).
  def chat_id_for(connection, message, client)
    phone = message.conversation.contact.phone_number.to_s.delete('^0-9')
    cached = ::Redis::Alfred.get("whatsapp_hybrid:chat_id:#{connection.session_name}:#{phone}")
    return cached if cached.present?

    result = client.check_contact_exists(phone: phone, session: connection.session_name)
    result['numberExists'] ? result['chatId'] : nil
  end
end
