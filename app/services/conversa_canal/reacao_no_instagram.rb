# Reação do atendente pela API do Instagram (#2113), para a caixa Instagram (login do Instagram). Corpo da doc da Meta:
#   reagir:     { recipient: { id: <IGSID> }, sender_action: 'react', payload: { message_id: <mid>, reaction: <emoji> } }
#   tirar:      { recipient: { id: <IGSID> }, sender_action: 'unreact', payload: { message_id: <mid> } }
#   https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api
# Como na Cloud API, só a mensagem recebida do cliente e com a janela padrão aberta: 24 h desde a última mensagem do
# cliente. A janela de 7 dias (ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT) vale para o texto por causa da tag HUMAN_AGENT,
# que a doc não diz que vale para sender_action; a reação vai sem tag e fica nas 24 h.
# A linha que o agente da Autonomia cria para a reação do cliente (autonomia_reaction) não é mensagem da Meta: não reage.
# Recusa da Meta: nada é gravado (ConversaCanal::ReacaoDoAtendente grava só depois do aceite).
class ConversaCanal::ReacaoNoInstagram
  TIMEOUT = 15
  # Token vencido ou revogado (o mesmo tratamento do envio de mensagem, Instagram::BaseSendService).
  TOKEN_INVALIDO = 190
  JANELA = Conversations::MessageWindowService::MESSAGING_WINDOW_24_HOURS
  ERROS_DE_REDE = [HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED,
                   Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError].freeze

  def initialize(message:)
    @message = message
  end

  def validar!
    recusar!(:so_recebida) unless @message.incoming?
    recusar_como_as_outras!(:mensagem_invalida) if da_autonomia?
    recusar!(:sem_identificacao) if @message.source_id.blank? || destinatario.blank?
    recusar!(:fora_da_janela) unless janela_aberta?
  end

  def enviar(emoji)
    response = HTTParty.post(url, query: { access_token: canal.access_token }, headers: { 'Content-Type' => 'application/json' },
                                  body: corpo(emoji).to_json, timeout: TIMEOUT)
    return if response.success? && erro_da_meta(response).blank?

    recusada!(response)
  rescue *ERROS_DE_REDE => e
    Rails.logger.warn("[conversa_canal][reacao] instagram unreachable message=#{@message.id} #{e.class}")
    recusar!(:provedor_fora)
  end

  private

  def da_autonomia?
    @message.content_attributes.to_h.stringify_keys.key?('autonomia_reaction')
  end

  # A última mensagem do cliente, como no Conversations::MessageWindowService.
  def janela_aberta?
    ultima = @message.conversation.messages.where(account_id: @message.account_id).incoming.last
    ultima.present? && Time.current < ultima.created_at + JANELA
  end

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

  # A frase comum a todos os canais (conversa_canal.reacoes.*).
  def recusar_como_as_outras!(codigo)
    raise ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t("conversa_canal.reacoes.#{codigo}")
  end
end
