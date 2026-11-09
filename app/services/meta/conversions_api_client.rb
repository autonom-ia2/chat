# Thin HTTP client for Meta's Conversions API for Business Messaging (CAPI-BM).
#
# POST /{API_VERSION}/{DATASET_ID}/events — action_source "business_messaging".
# This is NOT the classic Pixel /{pixel_id}/events endpoint; the attribution key is
# the ctwa_clid carried inside each event's user_data (see PayloadBuilder), not an
# event_id (Meta does not dedup CAPI-BM events server-side).
# The website mode (#1011) reuses this client with the funnel's Pixel id as dataset_id:
# same POST /{id}/events shape, events built by Crm::MetaCapi::WebsitePayloadBuilder.
#
# Whether Meta may have kept the event decides if it can be sent again (#2738, #2799), since
# Meta does not dedup: the connection (TCP and the SSL handshake) is opened before the request
# is written, so a failure there surely sent nothing and can be retried. Any failure after it,
# and a 5xx answer (Meta may have stored the event before failing), is an unknown outcome.
#
# The access token is a Meta secret: it travels only in the Authorization header (never
# the query string, which leaks through access logs/proxies/referrers) and is NEVER
# returned or logged. Every string that leaves this client (body/error) is scrubbed of
# token-shaped substrings before it can reach a log or exception.
class Meta::ConversionsApiClient
  BASE_URI = 'https://graph.facebook.com'.freeze
  # Pin the current stable Graph version (never v16.0). Reuses the same knob the
  # WhatsApp Cloud client reads, so the whole Meta surface moves versions together.
  DEFAULT_API_VERSION = 'v22.0'.freeze
  DEFAULT_TIMEOUT_SECONDS = 8
  # Meta answered, but failed on its side after it may have stored the event (#2799).
  SERVER_ERROR_HTTP = (500..599)
  # Any run of 20+ non-space chars is treated as a possible secret and redacted. Broad
  # on purpose: Meta tokens can carry -, _, |, +, /, = so a [A-Za-z0-9] class misses them.
  SENSITIVE_PATTERN = %r{[A-Za-z0-9_\-|+/=.]{20,}}

  # error_code: Meta's numeric error code (190 invalid token, 10/200-299 permission, …), nil on
  # success or network failure. Lets callers tell a dead token from a passing outage.
  # error_subcode refines it (100 with 33: the dataset no longer exists or cannot be reached).
  # unknown_outcome: the call failed after it may have reached Meta (no answer read, #2738) or
  # Meta answered a 5xx (#2799), so the event may have been kept; sending it again could count
  # it twice.
  Result = Struct.new(:ok, :http_code, :body, :error, :error_code, :error_subcode, :unknown_outcome, keyword_init: true) do
    # Never on an unknown outcome: a 5xx carrying 100/33 may still have kept the event (#2799).
    def dataset_gone?
      !unknown_outcome && error_code == 100 && error_subcode == 33
    end
  end

  def initialize(access_token:, dataset_id:, api_version: nil)
    @access_token = access_token
    @dataset_id = dataset_id
    @api_version = api_version.presence || GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT_API_VERSION)
  end

  # events: an array of CAPI-BM event hashes (see Crm::MetaCapi::PayloadBuilder#build).
  # The request is built and the connection opened before anything is written, so a failure
  # there never reads as an unknown outcome.
  def post_events(events)
    request = build_request(events)
    http = connection
    http.start
    connected = true
    answer(http.request(request))
  rescue StandardError => e
    Result.new(ok: false, http_code: nil, body: nil, error: sanitize(e.message), unknown_outcome: connected == true)
  ensure
    close(http)
  end

  private

  def uri
    URI("#{BASE_URI}/#{@api_version}/#{@dataset_id}/events")
  end

  def build_request(events)
    Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}").tap do |request|
      request.body = { data: Array(events) }.to_json
    end
  end

  # No proxy from the environment (nil), as with HTTParty before.
  def connection
    Net::HTTP.new(uri.host, uri.port, nil).tap do |http|
      http.use_ssl = true
      http.open_timeout = http.read_timeout = http.write_timeout = DEFAULT_TIMEOUT_SECONDS
    end
  end

  # Closing must not turn an answer already read into an error.
  def close(http)
    http.finish if http&.started?
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def answer(response)
    http_code = response.code.to_i
    body = sanitize(response.body)
    return Result.new(ok: true, http_code: http_code, body: body) if response.is_a?(Net::HTTPSuccess)

    error = meta_error(response.body)
    Result.new(ok: false, http_code: http_code, body: body, error: body, error_code: error['code'], error_subcode: error['error_subcode'],
               unknown_outcome: SERVER_ERROR_HTTP.cover?(http_code))
  end

  # The `error` object of Meta's answer, or {} when the body has none it can read.
  def meta_error(raw_body)
    error = JSON.parse(raw_body.to_s)
    error = error['error'] if error.is_a?(Hash)
    error.is_a?(Hash) ? error : {}
  rescue JSON::ParserError
    {}
  end

  def sanitize(text)
    return if text.nil?

    text.to_s.gsub(SENSITIVE_PATTERN, '<REDACTED>')
  end
end
