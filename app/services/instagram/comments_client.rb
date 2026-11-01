# Comentários do Instagram pela Graph do login do Instagram (#2196), com o token da caixa (Channel::Instagram):
# ler os comentários de uma mídia, responder em público, ocultar, apagar e responder no privado (Private Reply).
#
# - Ler, responder, ocultar e apagar pedem `instagram_business_manage_comments`; o privado vai pela API de mensagens
#   (`instagram_business_manage_messages`, a mesma do Direct da caixa), uma vez só, até 7 dias depois do comentário.
# - Devolve Meta::AdsGraphClient::Result: o mesmo `scope_error?` (10, 200–299), `token_invalid?` (190) e
#   `transient?` do cliente de anúncios, para quem chama separar falta de permissão de falha passageira.
# - O login do Instagram recebe o token na query. Por isso o log só leva o caminho, o HTTP e o código da Meta: nunca a
#   URL nem a mensagem de erro, que pode repetir o texto enviado (#2327).
# - O texto da resposta vai no corpo, nunca na query (#2327): a query fica na URL, e a URL vai a log, trace e span.
# https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/comment-moderation
class Instagram::CommentsClient
  TIMEOUT_SECONDS = 8
  PAGE_LIMIT = 25
  FIELDS = 'id,text,timestamp,hidden,from{id,username}'.freeze
  COMMENT_FIELDS = "#{FIELDS},replies{#{FIELDS}}".freeze
  Result = Meta::AdsGraphClient::Result
  # A Graph não respondeu (rede, 5xx, limite): quem roda em job sobe para o retry.
  class Unavailable < StandardError; end
  # Sem resposta da Meta: quem chama trata como "pode ter chegado" (http_code nil). Qualquer outro erro é nosso e sobe.
  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Net::ProtocolError, Timeout::Error, EOFError,
                    SocketError, SystemCallError, OpenSSL::SSL::SSLError, Zlib::Error, HTTParty::Error].freeze

  def initialize(channel)
    @channel = channel
  end

  def comments(media_id, after: nil)
    request(:get, "#{media_id}/comments", { fields: COMMENT_FIELDS, limit: PAGE_LIMIT, after: after }.compact)
  end

  def comments_count(media_id)
    request(:get, media_id.to_s, { fields: 'comments_count' })
  end

  # A legenda do post, para a IA que cuida dos comentários (#2424).
  def caption(media_id)
    request(:get, media_id.to_s, { fields: 'caption' })
  end

  # Um comentário só, com a mídia dele: quem age confere que ele é do anúncio; o webhook lê o texto aqui.
  def comment(comment_id)
    request(:get, comment_id.to_s, { fields: 'id,text,timestamp,parent_id,from{id,username},media{id}' })
  end

  # Em formulário: com JSON, a Graph do login do Instagram recusou a resposta em produção (400, código 24, #2330).
  def reply(comment_id, text)
    request(:post, "#{comment_id}/replies", {}, body: { message: text })
  end

  def hide(comment_id, hidden:)
    request(:post, comment_id.to_s, { hide: hidden })
  end

  def delete(comment_id)
    request(:delete, comment_id.to_s, {})
  end

  # → { recipient_id, message_id }: o IGSID de quem comentou e a mensagem no Direct.
  def private_reply(comment_id, text)
    request(:post, "#{@channel.instagram_id}/messages", {},
            body: { recipient: { comment_id: comment_id }, message: { text: text } }.to_json,
            headers: { 'Content-Type' => 'application/json' })
  end

  private

  def request(verb, path, query, **)
    response = HTTParty.public_send(verb, "#{base_uri}/#{path}", query: query.merge(access_token: @channel.access_token),
                                                                 timeout: TIMEOUT_SECONDS, **)
    log_failure(verb, path, build_result(response))
  rescue *NETWORK_ERRORS => e
    log_failure(verb, path, Result.new(ok: false, http_code: nil, data: nil, error_code: nil, error_message: e.class.name))
  end

  def build_result(response)
    body = JSON.parse(response.body.to_s)
    return Result.new(ok: true, http_code: response.code, data: body) if response.success? && body.is_a?(Hash)

    error = body.is_a?(Hash) ? body['error'].to_h : {}
    Result.new(ok: false, http_code: response.code, data: nil, error_code: error['code'],
               error_message: sanitize(error['message'].presence || "HTTP #{response.code}"))
  rescue JSON::ParserError
    Result.new(ok: false, http_code: response.code, data: nil, error_code: nil, error_message: "HTTP #{response.code}")
  end

  def log_failure(verb, path, result)
    return result if result.ok

    Rails.logger.warn("[InstagramComments] #{verb.to_s.upcase} #{path} http=#{result.http_code.inspect} " \
                      "code=#{result.error_code.inspect}")
    result
  end

  def sanitize(text)
    text.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
