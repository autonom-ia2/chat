# IA cuida dos comentários (#2212): as ações na Página do Facebook, com o token da caixa do Messenger.
# - privado: POST /{page_id}/messages com recipient.comment_id (Private Replies da Messenger Platform, pages_messaging);
# - resposta pública: POST /{comment_id}/comments;
# - esconder: POST /{comment_id} com is_hidden.
#
# Mesmas regras do Meta::AdsGraphClient: o token vai só no cabeçalho Authorization, a versão da Graph é a do resto da
# superfície Meta, e o erro da Meta passa pela limpeza de trechos com cara de segredo antes de ir para log ou tela.
class Crm::MetaAds::ComentariosIa::Rede::Pagina
  TIMEOUT_SECONDS = 8

  def initialize(channel)
    @channel = channel
  end

  def private_reply(comment_id, mensagem)
    enviar("#{@channel.page_id}/messages", recipient: { comment_id: comment_id }, message: mensagem, messaging_type: 'RESPONSE')
  end

  def reply(comment_id, texto)
    enviar("#{comment_id}/comments", message: texto)
  end

  def hide(comment_id)
    enviar(comment_id.to_s, is_hidden: true)
  end

  private

  def enviar(caminho, corpo)
    response = HTTParty.post("#{Meta::ConversionsApiClient::BASE_URI}/#{versao}/#{caminho}",
                             body: corpo.to_json, timeout: TIMEOUT_SECONDS,
                             headers: { 'Authorization' => "Bearer #{@channel.page_access_token}", 'Content-Type' => 'application/json' })
    envio(response)
  rescue StandardError => e
    falha("#{e.class}: #{e.message}")
  end

  def envio(response)
    dados = JSON.parse(response.body.to_s)
    return falha(erro(dados)) unless response.success? && dados.is_a?(Hash) && dados['error'].blank?

    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: dados['recipient_id'], message_id: dados['message_id'])
  rescue JSON::ParserError
    falha("HTTP #{response.code}")
  end

  def erro(dados)
    detalhe = dados.is_a?(Hash) ? dados['error'].to_h : {}
    "#{detalhe['code']} - #{detalhe['message']}"
  end

  def falha(texto)
    limpo = texto.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
    Rails.logger.warn("[comentarios_ia][pagina] page=#{@channel.page_id} erro=#{limpo}")
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: limpo)
  end

  def versao
    GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end
end
