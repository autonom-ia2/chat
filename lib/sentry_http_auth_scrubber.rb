require 'uri'
require 'json'

# Sentry 5.x exports HTTP queries independently of Rails parameter filtering.
# Keep the SDK event objects (and existing callbacks), filtering only credentials
# and HTTP URL/query fields before either event type reaches its transport.
module SentryHttpAuthScrubber
  FILTERED = '[FILTERED]'.freeze
  SECRET_KEYS = %w[
    access_token refresh_token id_token client_secret app_secret appsecret_proof
    password token secret authorization proxy_authorization cookie set_cookie x_api_key
    fb_dtsg lsd x_fb_lsd signed_request session_json
  ].freeze
  OAUTH_KEYS = %w[code state].freeze
  QUERY_KEYS = %w[query query_string http.query].freeze
  BODY_KEYS = %w[body data http.request.body].freeze
  AUTH_CONTAINER_KEYS = (QUERY_KEYS + %w[request body http.request.body]).freeze
  HTTP_URL_KEYS = %w[url uri http.url http.target].freeze
  URL_KEYS = (HTTP_URL_KEYS + %w[description message value]).freeze
  REQUEST_FIELDS = %w[url data query_string cookies headers env].freeze

  module_function

  def install(config)
    config.before_send = wrap(config.before_send)
    config.before_send_transaction = wrap(config.before_send_transaction)
  end

  def wrap(callback)
    lambda do |event, hint|
      event = scrub(event)
      next event unless callback && event

      scrub(callback.call(event, hint))
    rescue StandardError
      # Never return the original payload or forward a parser/callback exception
      # to SDK logging, which could contain the raw credentials. Drop this item.
      nil
    end
  end

  def scrub(value, key = nil, oauth: false)
    return FILTERED if secret_key?(key, oauth: oauth)

    oauth ||= AUTH_CONTAINER_KEYS.include?(key.to_s.downcase)
    scrub_value(value, key, oauth: oauth)
  end

  def scrub_value(value, key, oauth:)
    case value
    when Hash
      value.to_h { |child_key, child| [child_key, scrub(child, child_key, oauth: oauth)] }
    when Array
      value.map { |child| scrub(child, key, oauth: oauth) }
    when String
      scrub_string(value, key.to_s.downcase)
    else
      scrub_sdk(value)
    end
  end

  def scrub_sdk(value)
    case value
    when Sentry::Event
      scrub_event(value)
    when Sentry::Span
      scrub_span(value)
    when Sentry::BreadcrumbBuffer
      buffer = Sentry::BreadcrumbBuffer.new(value.buffer.size)
      value.each { |crumb| buffer.record(scrub(crumb)) }
      buffer
    when Sentry::Breadcrumb
      value.dup.tap do |crumb|
        crumb.data = scrub(crumb.data)
        crumb.message = scrub(crumb.message, :message)
      end
    else
      value
    end
  end

  def scrub_span(span)
    span.set_description(scrub(span.description, :description))
    span.data.replace(scrub(span.data))
    span.tags.replace(scrub(span.tags))
    span
  end

  def scrub_event(event)
    Sentry::Event::WRITER_ATTRIBUTES.each do |field|
      event.public_send("#{field}=", scrub(event.public_send(field), field))
    end
    scrub_request(event.request) if event.request
    event.spans = scrub(event.spans) if event.is_a?(Sentry::TransactionEvent)
    scrub_exceptions(event.exception) if event.is_a?(Sentry::ErrorEvent) && event.exception
    event
  end

  def scrub_exceptions(interface)
    # ExceptionInterface#values is an Array, not Hash#values.
    exceptions = interface.values
    exceptions.each { |exception| exception.value = scrub(exception.value, :value) }
  end

  def scrub_request(request)
    REQUEST_FIELDS.each do |field|
      request.public_send("#{field}=", scrub(request.public_send(field), field, oauth: true))
    end
  end

  def secret_key?(key, oauth: false)
    normalized = key.to_s.downcase.tr('-', '_').delete_prefix('http_')
    normalized = normalized.split('.').last.to_s.split('[').first
    SECRET_KEYS.include?(normalized) || normalized == 'cookies' || (oauth && OAUTH_KEYS.include?(normalized))
  end

  def scrub_string(value, key)
    return scrub_query(value) if QUERY_KEYS.include?(key)
    return scrub_body(value) if BODY_KEYS.include?(key)
    return value unless URL_KEYS.include?(key) || value.include?('://')
    return scrub_url(value) if HTTP_URL_KEYS.include?(key)

    scrub_text(value)
  end

  def scrub_text(value)
    value.split.reduce(value) do |text, token|
      next text unless token.include?('://') || token.include?('?') || token.include?('#')

      text.gsub(token, scrub_url(token))
    end
  end

  def scrub_body(value)
    if value.lstrip.start_with?('{', '[')
      parsed = JSON.parse(value)
      filtered = scrub(parsed, oauth: true)
      filtered == parsed ? value : JSON.generate(filtered)
    elsif value.include?('=')
      scrub_query(value)
    else
      value
    end
  rescue JSON::ParserError, ArgumentError
    FILTERED
  end

  def scrub_url(value)
    uri = URI.parse(value)
    if uri.userinfo
      # URI#userinfo= ignores nil; clear both components explicitly.
      uri.password = nil
      uri.user = nil
    end
    uri.query = scrub_query(uri.query) if uri.query
    uri.fragment = scrub_query(uri.fragment) if uri.fragment&.include?('=')
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    FILTERED
  end

  def scrub_query(value)
    pairs = URI.decode_www_form(value)
    return value unless pairs.any? { |key, _| secret_key?(key, oauth: true) }

    URI.encode_www_form(pairs.map { |key, item| [key, secret_key?(key, oauth: true) ? FILTERED : item] })
  rescue ArgumentError
    FILTERED
  end
end
