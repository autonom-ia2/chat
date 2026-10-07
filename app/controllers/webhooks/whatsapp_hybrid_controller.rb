# Webhook do motor WAHA para a sessão auxiliar do WhatsApp Híbrido (chat#1067).
# Só recebe estado da sessão e confirmação de entrega. Autentica pelo HMAC sha512 do corpo cru com o
# segredo da conexão; o public_id do endereço não é segredo.
class Webhooks::WhatsappHybridController < ActionController::API
  def create
    connection = WhatsappHybrid::Connection.find_by(public_id: params[:public_id])
    return head :not_found if connection.nil?
    return head :unauthorized unless valid_signature?(connection)

    event = params[:event].to_s
    return head :ok unless WhatsappHybrid::SessionManager::WEBHOOK_EVENTS.include?(event)

    WhatsappHybrid::WebhookEventJob.perform_later(connection.id, event, params[:payload]&.to_unsafe_h || {})
    head :ok
  end

  private

  def valid_signature?(connection)
    received = request.headers['X-Webhook-Hmac'].to_s
    return false if received.blank? || connection.webhook_secret.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA512', connection.webhook_secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(expected, received)
  end
end
