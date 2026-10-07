require 'ssrf_filter'

module SafeFetch
  DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES = %w[image/ video/].freeze
  DEFAULT_ALLOWED_CONTENT_TYPES = [].freeze
  DEFAULT_SENSITIVE_HEADERS = %w[authorization cookie proxy-authorization].freeze
  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 20
  DEFAULT_MAX_BYTES_FALLBACK_MB = 40
  # Redirecionamentos seguidos por padrão: os do ssrf_filter, que revalida o endereço a cada salto.
  # `max_redirects: 0` recusa o primeiro 3xx como `HttpError` — sem ler o corpo dele e sem ir aonde aponta.
  DEFAULT_MAX_REDIRECTS = SsrfFilter::DEFAULT_MAX_REDIRECTS
  # O ssrf_filter conecta num IP SORTEADO entre os do site. Num servidor sem rota IPv6, um site com
  # IPv4 e IPv6 falhava em metade das leituras ("No route to host"). Preferir IPv4 quando o site tem
  # resolve isso; a checagem de endereço privado do ssrf_filter continua valendo sobre o que sair daqui.
  DEFAULT_RESOLVER = proc do |hostname|
    enderecos = SsrfFilter::DEFAULT_RESOLVER.call(hostname)
    ipv4 = enderecos.select(&:ipv4?)
    ipv4.presence || enderecos
  end
  # Sem prazo por padrão: `open_timeout` e `read_timeout` valem por operação, como sempre. Quem passa
  # `total_timeout:` ganha um prazo monotônico para o CORPO, com teto por leitura, que também limita a
  # conexão e a espera pelos cabeçalhos como teto por operação — o que ele NÃO cobre (DNS, cabeçalhos
  # que gotejam, linhas de controle do chunked) está em `SafeFetch::Deadline`.
  DEFAULT_TOTAL_TIMEOUT = nil

  # `url` is where the redirects ended (the base for the page's relative addresses) and `charset` the one the
  # Content-Type announced, lower-case — both nil when unknown.
  Result = Data.define(:tempfile, :filename, :content_type, :url, :charset) do
    def initialize(tempfile:, filename:, content_type:, url: nil, charset: nil)
      super
    end

    def original_filename
      filename
    end
  end

  class Error < StandardError; end
  class InvalidUrlError < Error; end
  class UnsafeUrlError < Error; end
  class FetchError < Error; end

  # `status` é o código HTTP como inteiro: o que um chamador pode registrar sem carregar a frase do servidor
  # (`message` traz "404 Not Found", e a frase vem de fora).
  class HttpError < Error
    attr_reader :status

    def initialize(message = nil, status: nil)
      @status = status
      super(message)
    end
  end

  class FileTooLargeError < Error; end
  class UnsupportedContentTypeError < Error; end
  class UnsupportedMethodError < Error; end
  # O prazo (`total_timeout:`) venceu antes de a transferência acabar. É um `FetchError`, para quem já
  # trata falha de rede não precisar aprender uma classe nova.
  class TotalTimeoutError < FetchError; end

  def self.fetch(url, **, &)
    raise ArgumentError, 'block required' unless block_given?

    SafeFetch::Fetcher.new(SafeFetch::RequestOptions.new(url: url, **)).fetch(&)
  rescue SsrfFilter::InvalidUriScheme, URI::InvalidURIError => e
    raise InvalidUrlError, e.message
  rescue SsrfFilter::Error, Resolv::ResolvError => e
    raise UnsafeUrlError, e.message
  end

  def self.allow_private_network?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('SAFE_FETCH_ALLOW_PRIVATE_NETWORK', false))
  end
end
