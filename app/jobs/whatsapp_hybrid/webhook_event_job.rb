# Aplica um evento do webhook do WAHA à conexão híbrida (chat#1067).
# - session.status: grava o estado; a queda vira aviso aos administradores (SessionManager#apply_status!).
#   Traz também o limite de conversas novas (me.reachoutTimelock), que o envio usa sem consultar o motor (chat#1486).
# - message.ack: leva o ✓✓ / lido às mensagens que saíram pelo WhatsApp API. O ack de mensagem RECEBIDA (fromMe=false),
#   a leitura feita no celular do negócio, vai para WhatsappHybrid::LeituraNoCelular (#2246).
class WhatsappHybrid::WebhookEventJob < ApplicationJob
  queue_as :default

  # Números do WAHA: 1 servidor, 2 aparelho, 3 lido, 4 ouvido.
  ACK_STATUS = { 2 => 'delivered', 3 => 'read', 4 => 'read' }.freeze
  # Leitura no celular de mensagem ainda sem índice (#2246): até 3 novas tentativas, cobrindo ~1 min de fila.
  ESPERAS_SEM_INDICE = [5.seconds, 15.seconds, 45.seconds].freeze

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
    WhatsappHybrid::Capping.new(connection).apply!(payload['capping']) if payload['capping'].is_a?(Hash)
    WhatsappHybrid::Timelock.new(connection).apply!(payload['timelock']) if payload['timelock'].is_a?(Hash)
  end

  def apply_ack(connection, payload)
    return ler_no_celular(connection, payload) if payload['from_me'] == false

    status = ACK_STATUS[payload['ack'].to_i]
    return if status.nil?

    message = WhatsappHybrid::WebTransport.message_for(connection, payload['id'].to_s.split('_').last)
    Messages::StatusUpdateService.new(message, status).perform if message
  end

  # O índice da recebida é gravado no fim do Webhooks::WhatsappEventsJob (outra fila, depois da transação). Com a
  # conversa aberta no celular, o ack chega antes: sem esta nova tentativa, a leitura sumiria (o aparelho não reenvia).
  def ler_no_celular(connection, payload)
    motivo = WhatsappHybrid::LeituraNoCelular.new(connection).aplicar(payload)
    tentativa = payload['tentativa'].to_i
    return unless motivo == :sem_indice && tentativa < ESPERAS_SEM_INDICE.size

    self.class.set(wait: ESPERAS_SEM_INDICE[tentativa])
        .perform_later(connection.id, 'message.ack', payload.merge('tentativa' => tentativa + 1))
  end
end
