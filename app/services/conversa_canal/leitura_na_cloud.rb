# Lida pela Cloud API da Meta (#1702), para a caixa oficial e a híbrida. Corpo da doc da Meta:
#   POST /<phone_number_id>/messages { messaging_product: 'whatsapp', status: 'read', message_id: <wamid> }
#   https://developers.facebook.com/docs/whatsapp/cloud-api/guides/mark-message-as-read
# "When you mark a message as read, the API also marks earlier messages in the conversation as read." Prazo: até 30 dias
# depois do recebimento. Sem `typing_indicator`: o "digitando" é do robô (Conversations::ChannelTyping::Deliverer).
# Nunca levanta: devolve true quando a Meta aceitou. Recusa ou rede fora vira log info, sem token e sem corpo.
class ConversaCanal::LeituraNaCloud
  WAMID = 'wamid.'.freeze

  def initialize(message:, timeout:)
    @message = message
    @timeout = timeout
  end

  def enviar
    return false unless @message.source_id.to_s.start_with?(WAMID)

    response = HTTParty.post(url, headers: canal.provider_service.api_headers, body: corpo.to_json, timeout: @timeout)
    return true if response.success?

    Rails.logger.info("[conversa_canal][leitura] cloud refused message=#{@message.id} status=#{response.code}")
    false
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.info("[conversa_canal][leitura] cloud unreachable message=#{@message.id} #{e.class}")
    false
  end

  private

  def canal
    @message.inbox.channel
  end

  # Mesma versão e base da reação do atendente (ConversaCanal::ReacaoNaCloud).
  def url
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{ConversaCanal::ReacaoNaCloud::API_VERSION}/#{canal.provider_config['phone_number_id']}/messages"
  end

  def corpo
    { messaging_product: 'whatsapp', status: 'read', message_id: @message.source_id }
  end
end
