# Reação do atendente pela API do Instagram (#2113), para a caixa Instagram (login do Instagram). Corpo da doc da Meta:
#   reagir:     { recipient: { id: <IGSID> }, sender_action: 'react', payload: { message_id: <mid>, reaction: <emoji> } }
#   tirar:      { recipient: { id: <IGSID> }, sender_action: 'unreact', payload: { message_id: <mid> } }
#   https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api
# Como na Cloud API, só a mensagem recebida do cliente e com a janela de conversa aberta (a mesma regra do texto).
# Recusa da Meta: nada é gravado (ConversaCanal::ReacaoDoAtendente grava só depois do aceite).
class ConversaCanal::ReacaoNoInstagram
  TIMEOUT = 15
  # Token vencido ou revogado (o mesmo tratamento do envio de mensagem, Instagram::BaseSendService).
  TOKEN_INVALIDO = 190

  def initialize(message:)
    @message = message
  end

  def validar!
    recusar!(:so_recebida) unless @message.incoming?
    recusar!(:sem_identificacao) if @message.source_id.blank? || destinatario.blank?
    recusar!(:fora_da_janela) unless Conversations::MessageWindowService.new(@message.conversation).can_reply?
  end

  def enviar(emoji)
    response = HTTParty.post(url, query: { access_token: canal.access_token }, headers: { 'Content-Type' => 'application/json' },
                                  body: corpo(emoji).to_json, timeout: TIMEOUT)
    return if response.success? && erro_da_meta(response).blank?

    recusada!(response)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.warn("[conversa_canal][reacao] instagram unreachable message=#{@message.id} #{e.class}")
    recusar!(:provedor_fora)
  end

  private

  def canal
    @message.inbox.channel
  end

  def destinatario
    @message.conversation.contact_inbox&.source_id
  end

  def url
    versao = GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')
    "https://graph.instagram.com/#{versao}/#{canal.instagram_id.presence || 'me'}/messages"
  end

  def corpo(emoji)
    if emoji.empty?
      { recipient: { id: destinatario }, sender_action: 'unreact', payload: { message_id: @message.source_id } }
    else
      { recipient: { id: destinatario }, sender_action: 'react', payload: { message_id: @message.source_id, reaction: emoji } }
    end
  end

  def recusada!(response)
    Rails.logger.warn("[conversa_canal][reacao] instagram refused message=#{@message.id} status=#{response.code}")
    canal.authorization_error! if codigo_da_meta(response) == TOKEN_INVALIDO
    raise ConversaCanal::ReacaoDoAtendente::Recusa,
          I18n.t('conversa_canal.reacoes.instagram.provedor_recusou', motivo: erro_da_meta(response) || response.code)
  end

  # Formato do erro da Meta: { error: { message:, code: } }.
  def erro_da_meta(response)
    erro(response)&.dig('message').presence
  end

  def codigo_da_meta(response)
    erro(response)&.dig('code')
  end

  def erro(response)
    corpo = response.parsed_response
    corpo['error'] if corpo.is_a?(Hash) && corpo['error'].is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def recusar!(codigo)
    raise ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t("conversa_canal.reacoes.instagram.#{codigo}")
  end
end
