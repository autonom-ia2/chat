require 'net/http'
require 'resolv'
require 'uri'

# Baixa UMA página HTML de um endereço que veio de fora (site do lead). Todo destino, inclusive cada
# redirecionamento, passa pela UrlGuard, e a conexão vai para o IP que foi checado: o nome é resolvido uma vez,
# cada endereço passa pela guarda, e o Net::HTTP conecta naquele IP com o Host e o SNI do nome. Assim o DNS não
# tem como trocar a resposta entre a checagem e a conexão (#476). O corpo é lido até MAX_BODY_BYTES e o resto
# nem é baixado.
#
# Por que não o SafeFetch: ele recusa o corpo acima do teto (FileTooLargeError), e aqui o começo da página basta;
# e ele segue redirecionamento por dentro do ssrf_filter, sem passar cada salto pela UrlGuard.
class Autonomia::Prospecting::SafePageFetcher
  MAX_BODY_BYTES = 1.megabyte
  MAX_REDIRECTS = 2
  OPEN_TIMEOUT_SECONDS = 5
  READ_TIMEOUT_SECONDS = 8
  TOTAL_TIMEOUT_SECONDS = 20
  USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' \
               'Chrome/128.0.0.0 Safari/537.36'.freeze
  REQUEST_HEADERS = {
    'User-Agent' => USER_AGENT,
    'Accept' => 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
    'Accept-Language' => 'pt-BR,pt;q=0.9,en;q=0.8'
  }.freeze
  PAGE_CONTENT_TYPES = %w[text/html application/xhtml+xml text/plain].freeze
  DEFAULT_RESOLVER = ->(host) { Resolv.getaddresses(host) }
  UrlGuard = Autonomia::Agents::Knowledge::UrlGuard

  # Falha com código fechado (vira `error` no payload do scraper e `enrichment_error` no lead).
  class FetchFailed < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  # Estouro do prazo total. Fica só dentro do fetch, que o devolve como Net::ReadTimeout.
  class TotalTimeout < StandardError; end

  Page = Struct.new(:body, :uri, :charset, :truncated, keyword_init: true)

  def initialize(resolver: DEFAULT_RESOLVER)
    @resolver = resolver
  end

  # Devolve a Page. Levanta UrlGuard::BlockedUrl, FetchFailed ou o erro de rede do Net::HTTP.
  #
  # O prazo total cobre tudo: DNS, conexão, cabeçalhos, corpo e cada salto. O read_timeout vale por leitura, e um site
  # que manda um cabeçalho a cada poucos segundos segurava a thread do Sidekiq sem fim (#678). O Timeout só envolve
  # I/O de rede, sem transação nem escrita no banco. A classe do estouro é própria: o Net::HTTP pega Net::ReadTimeout e
  # Timeout::Error lá dentro e repete o GET, e a repetição rodava fora do prazo.
  def fetch(uri)
    Timeout.timeout(TOTAL_TIMEOUT_SECONDS, TotalTimeout) { fetch_following_redirects(uri) }
  rescue TotalTimeout
    raise Net::ReadTimeout
  end

  private

  def fetch_following_redirects(uri)
    current_uri = uri
    (MAX_REDIRECTS + 1).times do
      outcome = fetch_once(current_uri)
      return outcome if outcome.is_a?(Page)

      current_uri = URI.join(current_uri, outcome)
    end

    raise FetchFailed, 'too_many_redirects'
  end

  # Devolve a Page, ou o Location de um redirecionamento (que volta à guarda no salto seguinte).
  def fetch_once(uri)
    UrlGuard.new(uri.to_s).validate!
    http = pinned_http(uri)
    http.start do |connection|
      connection.request(Net::HTTP::Get.new(uri, REQUEST_HEADERS)) do |response|
        # `return` dentro do bloco: o Net::HTTP não lê o resto do corpo depois dele.
        return redirect_location(response) if response.is_a?(Net::HTTPRedirection)
        raise FetchFailed, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)

        return read_page(response, uri)
      end
    end
  end

  # Terceiro argumento nil desliga o proxy do ambiente: a conexão vai para o IP checado, não para outro host.
  def pinned_http(uri)
    Net::HTTP.new(uri.hostname, uri.port, nil).tap do |http|
      http.ipaddr = pinned_address(uri.hostname)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT_SECONDS
      http.ssl_timeout = OPEN_TIMEOUT_SECONDS
      http.read_timeout = READ_TIMEOUT_SECONDS
      http.write_timeout = READ_TIMEOUT_SECONDS
      # Sem o GET repetido por dentro do Net::HTTP depois de um erro de leitura: é site de fora, uma tentativa basta.
      http.max_retries = 0
    end
  end

  def pinned_address(hostname)
    addresses = @resolver.call(hostname).map(&:to_s)
    raise UrlGuard::BlockedUrl, 'blocked_host' if addresses.empty? || addresses.any? { |address| UrlGuard.blocked_ip?(address) }

    addresses.first
  end

  def redirect_location(response)
    location = response['location'].to_s
    raise FetchFailed, 'invalid_redirect' if location.blank?

    location
  end

  def read_page(response, uri)
    mime = response.content_type.to_s.downcase
    raise FetchFailed, 'unsupported_content_type' if mime.present? && PAGE_CONTENT_TYPES.exclude?(mime)

    body, truncated = read_limited_body(response)
    Page.new(body: body, uri: uri, charset: response.type_params['charset'], truncated: truncated)
  end

  # Lê até MAX_BODY_BYTES e para: o resto nem é baixado.
  def read_limited_body(response)
    body = +''
    truncated = catch(:body_limit) do
      response.read_body do |chunk|
        body << chunk
        throw :body_limit, true if body.bytesize >= MAX_BODY_BYTES
      end
      false
    end
    [body.byteslice(0, MAX_BODY_BYTES), truncated]
  end
end
