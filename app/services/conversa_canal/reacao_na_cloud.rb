# Reação do atendente pela Cloud API da Meta (#1702), para a caixa oficial e a híbrida (dentro da janela o híbrido
# manda tudo pela Cloud). Corpo da doc da Meta:
#   { messaging_product: 'whatsapp', recipient_type: 'individual', to: <telefone>, type: 'reaction',
#     reaction: { message_id: <wamid>, emoji: <emoji> } }
#   https://developers.facebook.com/docs/whatsapp/cloud-api/messages/reaction-messages
# Emoji vazio tira a reação. A Meta responde 200 e entrega a recusa depois (erro 131009, mensagem velha de 30 dias ou
# apagada) pelo webhook: aqui só há como avisar da recusa imediata.
class ConversaCanal::ReacaoNaCloud
  WAMID = 'wamid.'.freeze
  # Mesma versão do envio de anexos da Cloud API (Whatsapp::Providers::WhatsappCloudService).
  API_VERSION = 'v24.0'.freeze
  TIMEOUT = 15

  def initialize(message:)
    @message = message
  end

  def validar!
    recusar!(:so_recebida) unless @message.incoming?
    recusar!(:sem_identificacao) unless @message.source_id.to_s.start_with?(WAMID)
    recusar!(:fora_da_janela) unless Conversations::MessageWindowService.new(@message.conversation).can_reply?
  end

  def enviar(emoji)
    response = HTTParty.post(url, headers: provedor.api_headers, body: corpo(emoji).to_json, timeout: TIMEOUT)
    return if response.success? && erro_da_meta(response).blank?

    Rails.logger.warn("[conversa_canal][reacao] cloud refused message=#{@message.id} status=#{response.code}")
    raise ConversaCanal::ReacaoDoAtendente::Recusa,
          I18n.t('conversa_canal.reacoes.provedor_recusou', motivo: erro_da_meta(response) || response.code)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.warn("[conversa_canal][reacao] cloud unreachable message=#{@message.id} #{e.class}")
    recusar!(:provedor_fora)
  end

  private

  def canal
    @message.inbox.channel
  end

  def provedor
    canal.provider_service
  end

  def url
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{API_VERSION}/#{canal.provider_config['phone_number_id']}/messages"
  end

  def corpo(emoji)
    {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      **provedor.recipient_params(@message.conversation.contact_inbox.source_id),
      type: 'reaction',
      reaction: { message_id: @message.source_id, emoji: emoji }
    }
  end

  # Formato do erro da Meta: { error: { message: } }.
  # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
  def erro_da_meta(response)
    corpo = response.parsed_response
    corpo.dig('error', 'message').presence if corpo.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def recusar!(codigo)
    raise ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t("conversa_canal.reacoes.#{codigo}")
  end
end
