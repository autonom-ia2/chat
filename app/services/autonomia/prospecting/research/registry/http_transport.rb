require 'net/http'

# Transporte HTTP dos cadastros públicos. Só fala com os hosts fixos das quatro fontes, em https, com o User-Agent
# autonomia-radar/1.0. Não segue redirecionamento (o 3xx volta para o Hydrator, que passa para a próxima fonte) e não
# lê corpo acima de 1 MB. Corpo que não é JSON vira nil, e o parser o recusa como payload_malformed.
#
# Por que não o SafePageFetcher: aquele guarda endereço que veio de fora (site do lead). Aqui o destino é constante, e
# o que importa é o contrário: nunca sair dos quatro hosts.
class Autonomia::Prospecting::Research::Registry::HttpTransport
  USER_AGENT = 'autonomia-radar/1.0'.freeze
  REQUEST_HEADERS = { 'User-Agent' => USER_AGENT, 'Accept' => 'application/json' }.freeze
  MAX_BODY_BYTES = 1.megabyte
  ALLOWED_HOSTS = Autonomia::Prospecting::Research::Registry::PROVIDERS.to_set(&:host).freeze

  class BodyTooLarge < StandardError; end
  class HostNotAllowed < StandardError; end

  Response = Data.define(:status, :body, :headers)

  def request(url:, timeout:)
    uri = URI.parse(url)
    raise HostNotAllowed unless uri.scheme == 'https' && ALLOWED_HOSTS.include?(uri.host)

    http(uri, timeout).start do |connection|
      connection.request(Net::HTTP::Get.new(uri, REQUEST_HEADERS)) do |response|
        # `return` dentro do bloco: o Net::HTTP não lê o resto do corpo depois dele.
        return build_response(response)
      end
    end
  end

  private

  # Terceiro argumento nil desliga o proxy do ambiente.
  def http(uri, timeout)
    Net::HTTP.new(uri.host, uri.port, nil).tap do |http|
      http.use_ssl = true
      http.open_timeout = timeout
      http.ssl_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.max_retries = 0
    end
  end

  def build_response(response)
    status = response.code.to_i
    body = response.is_a?(Net::HTTPSuccess) ? parse_json(read_limited(response)) : nil
    Response.new(status: status, body: body, headers: { 'retry-after' => response['retry-after'] }.compact)
  end

  def read_limited(response)
    raise BodyTooLarge if response.content_length.to_i > MAX_BODY_BYTES

    body = +''
    response.read_body do |chunk|
      body << chunk
      raise BodyTooLarge if body.bytesize > MAX_BODY_BYTES
    end
    body
  end

  def parse_json(body)
    JSON.parse(body.force_encoding(Encoding::UTF_8))
  rescue JSON::ParserError
    nil
  end
end
