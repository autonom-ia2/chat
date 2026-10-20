# The Conversions API dataset of a WhatsApp Business Account (#1940). Meta keeps ONE
# dataset per WABA: GET /{waba_id}/dataset reads it, POST creates it or returns the one
# that already exists (Conversions API for Business Messaging, "Create a dataset").
#
# Same token rules as Meta::ConversionsApiClient: Authorization header only, nothing that
# leaves this client carries a token-shaped string. The WABA id must be numeric, so it
# can only name a WABA node in the Graph path.
class Meta::WabaDatasetClient
  BASE_URI = Meta::ConversionsApiClient::BASE_URI
  TIMEOUT_SECONDS = Meta::ConversionsApiClient::DEFAULT_TIMEOUT_SECONDS

  Result = Struct.new(:dataset_id, :error, keyword_init: true)

  def initialize(access_token:, waba_id:, api_version: nil)
    @access_token = access_token
    @waba_id = waba_id
    @api_version = api_version.presence ||
                   GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end

  # The WABA's dataset id, creating it only when Meta confirmed the WABA has none.
  def find_or_create
    return Result.new(error: 'invalid_waba_id') unless numeric_waba?

    found = existing
    return found if found.dataset_id.present? || found.error.present?

    create
  end

  private

  # GET answers { data: [{ id: }] }, an empty list when the WABA has none yet.
  def existing
    body, error = request(:get)
    return Result.new(error: error) if error
    return Result.new(error: 'unexpected_dataset_listing') unless body.is_a?(Hash) && body['data'].is_a?(Array)

    Result.new(dataset_id: body['data'].first&.dig('id').presence&.to_s)
  end

  # POST answers { id: } (the new dataset, or the one that already exists).
  def create
    body, error = request(:post)
    return Result.new(error: error) if error

    Result.new(dataset_id: (body['id'].presence&.to_s if body.is_a?(Hash)))
  end

  def numeric_waba?
    Integer(@waba_id.to_s, exception: false)&.positive?
  end

  # [parsed body, nil] on success, [nil, sanitized error] otherwise.
  def request(verb)
    response = HTTParty.public_send(verb, "#{BASE_URI}/#{@api_version}/#{@waba_id}/dataset",
                                    headers: { 'Authorization' => "Bearer #{@access_token}" },
                                    timeout: TIMEOUT_SECONDS)
    return [nil, sanitize(response.body.presence || "http #{response.code}")] unless response.success?

    [response.parsed_response, nil]
  rescue StandardError => e
    [nil, sanitize(e.message)]
  end

  def sanitize(text)
    text.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
  end
end
