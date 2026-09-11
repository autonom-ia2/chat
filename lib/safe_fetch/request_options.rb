class SafeFetch::RequestOptions
  DEFAULTS = {
    method: :get,
    body: nil,
    max_bytes: nil,
    open_timeout: SafeFetch::DEFAULT_OPEN_TIMEOUT,
    read_timeout: SafeFetch::DEFAULT_READ_TIMEOUT,
    total_timeout: SafeFetch::DEFAULT_TOTAL_TIMEOUT,
    max_redirects: SafeFetch::DEFAULT_MAX_REDIRECTS,
    headers: nil,
    sensitive_headers: [],
    resolver: SsrfFilter::DEFAULT_RESOLVER,
    http_basic_authentication: nil,
    allowed_content_type_prefixes: SafeFetch::DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES,
    allowed_content_types: SafeFetch::DEFAULT_ALLOWED_CONTENT_TYPES,
    validate_content_type: true
  }.freeze

  attr_reader :allowed_content_type_prefixes, :allowed_content_types, :body, :headers, :http_basic_authentication,
              :max_redirects, :method, :open_timeout, :read_timeout, :resolver, :sensitive_headers, :total_timeout, :uri, :url

  def initialize(url:, **options)
    config = DEFAULTS.merge(options)
    @url = url
    @uri = parse_and_validate_url!(url)
    @method = normalize_method(config[:method])
    @body = config[:body]
    @headers = normalize_headers(config[:headers])
    @sensitive_headers = normalize_sensitive_headers(config[:sensitive_headers])
    @resolver = config[:resolver]
    @http_basic_authentication = config[:http_basic_authentication]
    apply_limits(config)
    apply_content_type_rules(config)
  end

  def effective_max_bytes
    @effective_max_bytes ||= @max_bytes || default_max_bytes
  end

  def filename
    @filename ||= File.basename(uri.path).presence || "download-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
  end

  def request_options
    {
      headers: headers,
      body: body,
      request_proc: request_proc,
      resolver: resolver,
      sensitive_headers: sensitive_headers,
      max_redirects: max_redirects,
      http_options: { open_timeout: bounded_by_total(open_timeout), read_timeout: bounded_by_total(read_timeout) }
    }
  end

  def validate_content_type?
    @validate_content_type
  end

  def follow_redirects?
    max_redirects.positive?
  end

  private

  def apply_limits(config)
    @max_bytes = config[:max_bytes]
    @open_timeout = config[:open_timeout]
    @read_timeout = config[:read_timeout]
    @total_timeout = normalize_total_timeout(config[:total_timeout])
    @max_redirects = normalize_max_redirects(config[:max_redirects])
  end

  def apply_content_type_rules(config)
    @allowed_content_type_prefixes = Array(config[:allowed_content_type_prefixes])
    @allowed_content_types = Array(config[:allowed_content_types])
    @validate_content_type = config[:validate_content_type]
  end

  # Um prazo (`total_timeout`) menor que os tetos por operação tem de valer já na conexão e na espera
  # pelos cabeçalhos, que acontecem antes de o `Fetcher` receber a resposta e poder apertar o socket.
  # Aqui ele vale como TETO POR OPERAÇÃO, não como saldo: cabeçalhos que gotejam abaixo dele evadem
  # (ressalva registrada, ver `SafeFetch::Deadline`).
  def bounded_by_total(timeout)
    return timeout if total_timeout.nil?
    return total_timeout if timeout.nil?

    [timeout, total_timeout].min
  end

  def normalize_total_timeout(value)
    return value if value.nil? || (value.is_a?(Numeric) && value.positive?)

    raise ArgumentError, "total_timeout must be a positive number or nil, got #{value.inspect}"
  end

  def normalize_max_redirects(value)
    return value if value.is_a?(Integer) && value >= 0

    raise ArgumentError, "max_redirects must be a non-negative Integer, got #{value.inspect}"
  end

  def default_max_bytes
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', SafeFetch::DEFAULT_MAX_BYTES_FALLBACK_MB).to_i
    limit_mb = SafeFetch::DEFAULT_MAX_BYTES_FALLBACK_MB if limit_mb <= 0
    limit_mb.megabytes
  end

  def parse_and_validate_url!(value)
    parsed_uri = URI.parse(value)
    raise SafeFetch::InvalidUrlError, 'scheme must be http or https' unless parsed_uri.is_a?(URI::HTTP) || parsed_uri.is_a?(URI::HTTPS)
    raise SafeFetch::InvalidUrlError, 'missing host' if parsed_uri.host.blank?

    parsed_uri
  end

  def normalize_method(value)
    http_method = value.to_s.downcase.to_sym
    return http_method if SsrfFilter::VERB_MAP.key?(http_method)

    raise SafeFetch::UnsupportedMethodError, "unsupported method: #{value}"
  end

  def normalize_headers(value)
    value&.to_h
  end

  def normalize_sensitive_headers(value)
    (SafeFetch::DEFAULT_SENSITIVE_HEADERS + Array(value)).map { |header| header.to_s.downcase }.uniq
  end

  def request_proc
    proc do |request|
      credentials = http_basic_authentication.presence || basic_authentication_for(request.uri)
      request.basic_auth(*credentials) if credentials.present?
    end
  end

  def basic_authentication_for(request_uri)
    uri_basic_authentication(request_uri) || original_uri_basic_authentication(request_uri)
  end

  def original_uri_basic_authentication(request_uri)
    return unless same_origin?(request_uri, uri)

    uri_basic_authentication(uri)
  end

  def same_origin?(request_uri, other_uri)
    request_uri.scheme == other_uri.scheme && request_uri.hostname == other_uri.hostname && request_uri.port == other_uri.port
  end

  def uri_basic_authentication(value)
    return if value.user.blank?

    [
      URI.decode_uri_component(value.user),
      URI.decode_uri_component(value.password.to_s)
    ]
  end
end
