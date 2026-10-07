# Webhook do motor WAHA para a sessão auxiliar do WhatsApp Híbrido (chat#1067).
# Só recebe estado da sessão e confirmação de entrega. Autentica pelo HMAC sha512 do corpo cru com o
# segredo da conexão (comparação em tempo constante). Endereço desconhecido e assinatura inválida
# recebem a mesma resposta, e nada do corpo é usado antes de a assinatura conferir.
class Webhooks::WhatsappHybridController < ActionController::API
  # Eventos de estado e de confirmação têm poucos KB; acima disto não é o motor.
  MAX_BODY_BYTES = 64.kilobytes

  before_action :reject_oversized_body
  before_action :authenticate_engine

  def create
    body = JSON.parse(request.raw_post)
    return head :bad_request unless body.is_a?(Hash)

    event = body['event'].to_s
    return head :ok unless WhatsappHybrid::SessionManager::WEBHOOK_EVENTS.include?(event)

    WhatsappHybrid::WebhookEventJob.perform_later(@connection.id, event, used_fields(body['payload']))
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def reject_oversized_body
    head :payload_too_large if request.content_length.to_i > MAX_BODY_BYTES || request.raw_post.bytesize > MAX_BODY_BYTES
  end

  def authenticate_engine
    @connection = WhatsappHybrid::Connection.find_by(public_id: request.path_parameters[:public_id].to_s)
    head :unauthorized unless @connection && valid_signature?
  end

  def valid_signature?
    received = request.headers['X-Webhook-Hmac'].to_s.downcase
    return false if received.blank? || @connection.webhook_secret.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA512', @connection.webhook_secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(expected, received)
  end

  # Só o que o job usa: nada de dado pessoal sobrando na fila.
  def used_fields(payload)
    return {} unless payload.is_a?(Hash)

    me = payload['me'].is_a?(Hash) ? payload['me'].slice('id') : nil
    { 'status' => payload['status'], 'ack' => payload['ack'], 'id' => payload['id'], 'me' => me }.compact
  end
end
