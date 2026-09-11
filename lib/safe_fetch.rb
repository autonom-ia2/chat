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
  # Sem prazo total por padrão: `open_timeout` e `read_timeout` valem por operação, como sempre. Quem passa
  # `total_timeout:` ganha um prazo monotônico para a transferência inteira (ver `SafeFetch::Deadline`).
  DEFAULT_TOTAL_TIMEOUT = nil

  Result = Data.define(:tempfile, :filename, :content_type) do
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
  # O prazo total (`total_timeout:`) venceu antes de a transferência acabar. É um `FetchError`, para quem já
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
