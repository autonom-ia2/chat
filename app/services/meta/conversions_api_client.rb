# Thin HTTP client for Meta's Conversions API for Business Messaging (CAPI-BM).
#
# POST /{API_VERSION}/{DATASET_ID}/events — action_source "business_messaging".
# This is NOT the classic Pixel /{pixel_id}/events endpoint; the attribution key is
# the ctwa_clid carried inside each event's user_data (see PayloadBuilder), not an
# event_id (Meta does not dedup CAPI-BM events server-side).
# The website mode (#1011) reuses this client with the funnel's Pixel id as dataset_id:
# same POST /{id}/events shape, events built by Crm::MetaCapi::WebsitePayloadBuilder.
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
  # Any run of 20+ non-space chars is treated as a possible secret and redacted. Broad
  # on purpose: Meta tokens can carry -, _, |, +, /, = so a [A-Za-z0-9] class misses them.
  SENSITIVE_PATTERN = %r{[A-Za-z0-9_\-|+/=.]{20,}}

  # error_code: Meta's numeric error code (190 invalid token, 10/200-299 permission, …), nil on
  # success or network failure. Lets callers tell a dead token from a passing outage.
  # error_subcode refines it (100 with 33: the dataset no longer exists or cannot be reached).
  Result = Struct.new(:ok, :http_code, :body, :error, :error_code, :error_subcode, keyword_init: true) do
    def dataset_gone?
      error_code == 100 && error_subcode == 33
    end
  end

  def initialize(access_token:, dataset_id:, api_version: nil)
    @access_token = access_token
    @dataset_id = dataset_id
    @api_version = api_version.presence || GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT_API_VERSION)
  end

  # events: an array of CAPI-BM event hashes (see Crm::MetaCapi::PayloadBuilder#build).
  def post_events(events)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{@dataset_id}/events",
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      },
      body: { data: Array(events) }.to_json,
      timeout: DEFAULT_TIMEOUT_SECONDS
    )

    body = sanitize(response.body)
    return Result.new(ok: true, http_code: response.code, body: body) if response.success?

    error = meta_error(response.body)
    Result.new(ok: false, http_code: response.code, body: body, error: body, error_code: error['code'], error_subcode: error['error_subcode'])
  rescue StandardError => e
    Result.new(ok: false, http_code: nil, body: nil, error: sanitize(e.message))
  end

  private

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
