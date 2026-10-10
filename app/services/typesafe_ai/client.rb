require 'net/http'
require 'json'

class TypesafeAi::Client
  BASE_URI = URI('https://api.typesafe.ai').freeze
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 10
  MAX_RETRIES = 2

  class Error < StandardError
    attr_reader :code, :status

    def initialize(code, status: nil)
      @code = code
      @status = status
      super(code)
    end
  end

  def initialize(api_key: TypesafeAi::Config.api_key, sleeper: ->(seconds) { sleep(seconds) })
    @api_key = api_key.to_s
    @sleeper = sleeper
  end

  def models
    request(:get, '/v1/models').fetch('models')
  end

  def evaluate(state:, questions:, model: TypesafeAi::Config.model)
    request(:post, '/v1/systemone', body: { state: state, model: model, questions: questions })
  end

  private

  def request(method, path, body: nil)
    raise Error, 'typesafe_not_configured' if @api_key.blank?

    response = request_with_retries(method, path, body)
    raise Error.new(error_code(response.code.to_i), status: response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Error
    raise
  rescue JSON::ParserError
    raise Error, 'typesafe_invalid_response'
  rescue Timeout::Error, SocketError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH
    raise Error, 'typesafe_unavailable'
  end

  def request_with_retries(method, path, body)
    attempts = 0
    loop do
      response = perform_request(method, path, body)
      return response unless retryable_status?(response.code.to_i) && attempts < MAX_RETRIES

      attempts += 1
      @sleeper.call(retry_delay(response, attempts))
    end
  end

  def perform_request(method, path, body)
    uri = BASE_URI + path
    request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Accept'] = 'application/json'
    if body
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
    end

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
  end

  def error_code(status)
    case status
    when 401 then 'typesafe_invalid_key'
    when 422 then 'typesafe_invalid_request'
    when 429 then 'typesafe_rate_limited'
    when 529 then 'typesafe_overloaded'
    else 'typesafe_unavailable'
    end
  end

  def retryable_status?(status)
    status == 429 || status == 529 || status >= 500
  end

  def retry_delay(response, attempts)
    retry_after = response['retry-after'].to_f
    return [retry_after, 2.0].min if retry_after.positive?

    0.2 * (2**(attempts - 1))
  end
end
