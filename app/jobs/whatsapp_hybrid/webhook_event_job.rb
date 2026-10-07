# Aplica um evento do webhook do WAHA à conexão híbrida (chat#1067).
# - session.status: grava o estado; a queda vira aviso aos administradores (SessionManager#apply_status!).
# - message.ack: leva o ✓✓ / lido às mensagens que saíram pelo WhatsApp API.
class WhatsappHybrid::WebhookEventJob < ApplicationJob
  queue_as :default

  # Números do WAHA: 1 servidor, 2 aparelho, 3 lido, 4 ouvido.
  ACK_STATUS = { 2 => 'delivered', 3 => 'read', 4 => 'read' }.freeze

  def perform(connection_id, event, payload)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return if connection.nil?

    event == 'session.status' ? apply_session_status(connection, payload) : apply_ack(connection, payload)
  end

  private

  def apply_session_status(connection, payload)
    status = WhatsappHybrid::SessionManager::STATUS_MAP.fetch(payload['status'].to_s, 'connecting')
    phone = payload.dig('me', 'id').to_s.split('@').first.to_s.delete('^0-9').presence
    WhatsappHybrid::SessionManager.new(connection).apply_status!(status, phone: phone)
  end

  def apply_ack(connection, payload)
    status = ACK_STATUS[payload['ack'].to_i]
    return if status.nil?

    message = WhatsappHybrid::WebTransport.message_for(connection, payload['id'].to_s.split('_').last)
    Messages::StatusUpdateService.new(message, status).perform if message
  end
end
