# IA cuida dos comentários (#2212): o privado pelo Messenger, com o token da caixa: POST /{page_id}/messages com
# recipient.comment_id (Private Replies da Messenger Platform, pages_messaging). A resposta pública e o esconder são do
# Crm::MetaAds::FacebookComments (#2197).
#
# Mesmas regras do Meta::AdsGraphClient: o token vai só no cabeçalho Authorization, a versão da Graph é a do resto da
# superfície Meta, e o erro da Meta passa pela limpeza de trechos com cara de segredo antes de ir para log ou tela.
class Crm::MetaAds::ComentariosIa::Rede::Pagina
  TIMEOUT_SECONDS = 8
  # A chamada saiu e a resposta não voltou: a Meta pode ter entregado. Erro de código não entra aqui: sobe.
  SEM_RESPOSTA = [HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, SystemCallError,
                  OpenSSL::SSL::SSLError, EOFError].freeze

  def initialize(channel)
    @channel = channel
  end

  def private_reply(comment_id, mensagem)
    return falha('id_invalido') unless id_simples?(comment_id)

    enviar(@channel.page_id, '/messages', recipient: { comment_id: comment_id }, message: mensagem, messaging_type: 'RESPONSE')
  end

  private

  # Os ids entram no caminho da Graph: só dígitos e `_` (o id do comentário do Facebook é `<post>_<comentário>`), para
  # que `/`, `?` ou `&` não virem outro endereço chamado com o token da Página.
  def id_simples?(id)
    id.to_s.present? && id.to_s.each_char.all? { |char| char.between?('0', '9') || char == '_' }
  end

  def enviar(id, sufixo, corpo)
    return falha('id_invalido') unless id_simples?(id)

    response = HTTParty.post("#{Meta::ConversionsApiClient::BASE_URI}/#{versao}/#{id}#{sufixo}",
                             body: corpo.to_json, timeout: TIMEOUT_SECONDS,
                             headers: { 'Authorization' => "Bearer #{@channel.page_access_token}", 'Content-Type' => 'application/json' })
    envio(response)
  rescue *SEM_RESPOSTA => e
    falha("#{e.class}: #{e.message}", talvez_entregue: true)
  end

  # Sem resposta ou 5xx, a Meta pode ter entregado; 4xx é recusa.
  def envio(response)
    talvez = response.code.to_i >= 500
    dados = JSON.parse(response.body.to_s)
    return falha(erro(dados), talvez_entregue: talvez) unless response.success? && dados.is_a?(Hash) && dados['error'].blank?

    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: dados['recipient_id'], message_id: dados['message_id'])
  rescue JSON::ParserError
    falha("HTTP #{response.code}", talvez_entregue: talvez)
  end

  def erro(dados)
    detalhe = dados.is_a?(Hash) ? dados['error'].to_h : {}
    "#{detalhe['code']} - #{detalhe['message']}"
  end

  def falha(texto, talvez_entregue: false)
    limpo = texto.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
    Rails.logger.warn("[comentarios_ia][pagina] page=#{@channel.page_id} erro=#{limpo}")
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: limpo, talvez_entregue: talvez_entregue)
  end

  def versao
    GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end
end
