# The Conversions API dataset of a WhatsApp Business Account (#1940). Meta keeps ONE
# dataset per WABA: GET /{waba_id}/dataset reads it, POST creates it or returns the one
# that already exists (Conversions API for Business Messaging, "Create a dataset").
#
# Same token rules as Meta::ConversionsApiClient: Authorization header only, nothing that
# leaves this client carries a token-shaped string. The WABA id must be numeric, so it
# can only name a WABA node in the Graph path.
#
# `transient` tells a passing failure (network, 5xx, rate limit), worth a retry, from one
# that will fail the same way every time (bad WABA id, refused token or permission).
class Meta::WabaDatasetClient
  BASE_URI = Meta::ConversionsApiClient::BASE_URI
  TIMEOUT_SECONDS = Meta::ConversionsApiClient::DEFAULT_TIMEOUT_SECONDS
  OPEN_TIMEOUT_SECONDS = 2
  # Meta's throttling / temporary codes (Graph API error handling), and the HTTP statuses
  # that mean "try later" whatever the body says.
  TRANSIENT_CODES = [1, 2, 4, 17, 32, 341, 613, 80_007].freeze
  TRANSIENT_HTTP = [408, 429].freeze
  # The token is dead (190) or lacks the permission (10, 200-299): the inbox must be
  # reconnected, which the card says as 'missing_credentials'.
  ACCESS_CODES = [10, 190, *200..299].freeze
  # 100 with subcode 33 on the WABA node: it does not exist for this token, which also means
  # reconnecting (#2799), not "no dataset".
  UNREACHABLE_OBJECT = [100, 33].freeze
  # Only a network failure is passing. Any other exception is a bug of ours and raises (#2799).
  NETWORK_ERRORS = [Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError,
                    Net::HTTPBadResponse].freeze

  Result = Struct.new(:dataset_id, :error, :transient, :access_denied, keyword_init: true)

  def initialize(access_token:, waba_id:, api_version: nil)
    @access_token = access_token
    @waba_id = waba_id
    @api_version = api_version.presence ||
                   GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end

  # The WABA's dataset id, creating it only when Meta confirmed the WABA has none.
  def find_or_create
    return Result.new(error: 'invalid_waba_id', transient: false) unless numeric_waba?

    found = existing
    return found if found.dataset_id.present? || found.error.present?

    create
  end

  private

  # GET answers { data: [{ id: }] }, an empty list when the WABA has none yet.
  def existing
    body, failure = request(:get)
    return failure if failure
    return Result.new(error: 'unexpected_dataset_listing', transient: false) unless body.is_a?(Hash) && body['data'].is_a?(Array)

    Result.new(dataset_id: body['data'].first&.dig('id').presence&.to_s)
  end

  # POST answers { id: } (the new dataset, or the one that already exists).
  def create
    body, failure = request(:post)
    return failure if failure

    Result.new(dataset_id: (body['id'].presence&.to_s if body.is_a?(Hash)))
  end

  # Digits only: Integer() would also take surrounding spaces, which would land in the Graph path (#2799).
  def numeric_waba?
    waba = @waba_id.to_s
    waba.present? && waba.delete('0-9').empty? && waba.to_i.positive?
  end

  # [parsed body, nil] on success, [nil, failed Result] otherwise. The body is parsed here,
  # not by HTTParty, so a missing or odd Content-Type does not lose it.
  def request(verb)
    response = HTTParty.public_send(verb, "#{BASE_URI}/#{@api_version}/#{@waba_id}/dataset",
                                    headers: { 'Authorization' => "Bearer #{@access_token}" },
                                    timeout: TIMEOUT_SECONDS, open_timeout: OPEN_TIMEOUT_SECONDS)
    body = parse(response.body)
    return [body, nil] if response.success?

    [nil, failure(response.code, body, response.body)]
  rescue *NETWORK_ERRORS => e
    [nil, Result.new(error: sanitize(e.message), transient: true)]
  end

  def failure(http_code, body, raw)
    error = body.is_a?(Hash) ? body['error'] : nil
    return Result.new(error: sanitize(raw.presence || "http #{http_code}"), transient: transient?(http_code, nil)) unless error.is_a?(Hash)

    code = error['code'].to_i
    Result.new(error: sanitize("meta_error_#{code}: #{error['message']}"), transient: transient?(http_code, code),
               access_denied: ACCESS_CODES.include?(code) || [code, error['error_subcode'].to_i] == UNREACHABLE_OBJECT)
  end

  def transient?(http_code, code)
    http_code.to_i >= 500 || TRANSIENT_HTTP.include?(http_code.to_i) || TRANSIENT_CODES.include?(code)
  end

  def parse(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    nil
  end

  def sanitize(text)
    text.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
  end
end
