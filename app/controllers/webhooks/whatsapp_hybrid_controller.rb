# Webhook do motor WAHA para a sessão auxiliar do WhatsApp Híbrido (chat#1067).
# Só recebe estado da sessão e confirmação de entrega. Autentica pelo HMAC sha512 do corpo cru com o
# segredo da conexão (comparação em tempo constante). Endereço desconhecido e assinatura inválida
# recebem a mesma resposta, e nada do corpo é usado antes de a assinatura conferir.
# Contra reenvio (#1094): o `id` e o `timestamp` vêm dentro do corpo assinado. Evento fora da janela
# de 5 minutos é recusado; evento já visto (mesmo id) é aceito sem efeito.
class Webhooks::WhatsappHybridController < ActionController::API
  # Eventos de estado e de confirmação têm poucos KB; acima disto não é o motor.
  MAX_BODY_BYTES = 64.kilobytes
  MAX_CLOCK_SKEW_MS = 5.minutes.in_milliseconds
  SEEN_EVENT_TTL = 10.minutes.to_i

  before_action :reject_oversized_body
  before_action :authenticate_engine

  def create
    body = JSON.parse(request.raw_post)
    return head :bad_request unless body.is_a?(Hash) && fresh?(body)

    event = body['event'].to_s
    return head :ok unless WhatsappHybrid::SessionManager::WEBHOOK_EVENTS.include?(event)
    return head :ok unless first_delivery?(body['id'])

    WhatsappHybrid::WebhookEventJob.perform_later(@connection.id, event, used_fields(body))
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

  # O instante vem do corpo assinado (ms); o cabeçalho X-Webhook-Timestamp não é assinado.
  def fresh?(body)
    sent_at = body['timestamp']
    sent_at.is_a?(Numeric) && ((Time.current.to_f * 1000) - sent_at).abs <= MAX_CLOCK_SKEW_MS
  end

  def first_delivery?(event_id)
    return false if event_id.blank?

    ::Redis::Alfred.set("whatsapp_hybrid:evt:#{@connection.id}:#{event_id}", 1, nx: true, ex: SEEN_EVENT_TTL)
  end

  # Só o que o job usa: nada de dado pessoal sobrando na fila. `me` (o número conectado) vem no topo do evento.
  def used_fields(body)
    payload = body['payload'].is_a?(Hash) ? body['payload'] : {}
    me = body['me'].is_a?(Hash) ? body['me'].slice('id') : nil
    { 'status' => payload['status'], 'ack' => payload['ack'], 'id' => payload['id'], 'me' => me }.compact
  end
end
