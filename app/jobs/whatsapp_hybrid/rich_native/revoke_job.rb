# Apaga "para todos" no WhatsApp a mensagem apagada no painel (chat#1709, fase 3, WhatsappHybrid::RichNative::
# RevokeOnDelete), pela sessão do plano B. O motor (GOWS) exige o id serializado "true_<chatId>_<id físico>". A bolha já
# está apagada no painel: erro do motor (mensagem velha demais, sessão caída) vai ao log e ao rastreador SÓ com a classe
# e o status HTTP. A mensagem do Waha::Client::Error traz o caminho do pedido (telefone do cliente e da empresa) e o
# corpo da resposta: ela não sai daqui.
# Contrato com a pele do Max (#1793): confirmado o "apagar para todos" pelo motor (delete_message sem erro), a mensagem
# ganha `content_attributes.revogada_no_canal = true` (a pele mostra "Você apagou esta mensagem"; sem a chave, "só aqui,
# o cliente ainda vê"). Gravada sob trava, sem as validações do modelo; não reenvia nem pede outro apagar (o
# RevokeOnDelete só age na transição para `deleted`). Em erro do motor, não grava. Falha ao gravar a marca vai ao log
# (só a classe) e não refaz o job: o apagar já saiu.
class WhatsappHybrid::RichNative::RevokeJob < ApplicationJob
  queue_as :medium
  REVOKED_KEY = 'revogada_no_canal'.freeze

  # O que vai ao rastreador: sem telefone, sem caminho, sem corpo.
  class RevokeFailed < StandardError; end

  def perform(message_id, physical_id)
    message = Message.find_by(id: message_id)
    connection = message && WhatsappHybrid::Connection.find_by(inbox_id: message.inbox_id)
    return if connection.nil? || physical_id.blank?

    client = Waha::Client.new
    chat_id = chat_id_for(connection, message, client)
    return if chat_id.blank?

    client.delete_message(session: connection.session_name, chat_id: chat_id, message_id: "true_#{chat_id}_#{physical_id}")
    mark_revoked!(message)
  rescue Waha::Client::Error => e
    report(message_id, message, e)
  end

  private

  def mark_revoked!(message)
    message.with_lock do
      next if message.content_attributes.to_h[REVOKED_KEY] == true

      message.content_attributes = message.content_attributes.to_h.merge(REVOKED_KEY => true)
      message.save!(validate: false)
    end
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] revoke mark failed message=#{message.id} #{e.class}")
  end

  # O mesmo chat que o envio usa (cache do WebTransport; senão, a consulta ao motor).
  def chat_id_for(connection, message, client)
    phone = message.conversation.contact.phone_number.to_s.delete('^0-9')
    cached = ::Redis::Alfred.get("whatsapp_hybrid:chat_id:#{connection.session_name}:#{phone}")
    return cached if cached.present?

    result = client.check_contact_exists(phone: phone, session: connection.session_name)
    result['numberExists'] ? result['chatId'] : nil
  end

  def report(message_id, message, error)
    Rails.logger.warn("[whatsapp_hybrid] revoke failed message=#{message_id} #{error.class} status=#{error.status}")
    ChatwootExceptionTracker.new(RevokeFailed.new("#{error.class} status=#{error.status}"), account: message&.account).capture_exception
  end
end
