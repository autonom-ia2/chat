# Gera o token da BigDataCorp (POST /tokens/gerar) para o BigDataCorpClient (#679). Porte do generateToken do Orth:
# repete em timeout, 429 e 5xx, porque gerar token não é a consulta paga. Falha de rede sem timeout não repete.
# Credencial e token nunca aparecem em erro, log ou inspect (BigDataCorpClient::Redacted).
class Autonomia::Prospecting::Research::BigDataCorpTokenIssuer
  PATH = '/tokens/gerar'.freeze
  TOKEN_KEYS = %w[token accessToken AccessToken].freeze
  TOKEN_ID_KEYS = %w[tokenID tokenId TokenId].freeze

  def initialize(transport:, max_attempts:, ttl:)
    @transport = transport
    @max_attempts = max_attempts
    @ttl = ttl
  end

  def inspect = "#<#{self.class.name} [REDACTED]>"
  alias to_s inspect

  def issue(credentials)
    body = { login: credentials.username, password: credentials.password, expires: 1 }.to_json
    1.upto(@max_attempts) do |attempt|
      token = attempt_token(body, attempt)
      return token if token
    end
    raise client::Error.new('BIGDATACORP_TOKEN_UNAVAILABLE', phase: :token)
  end

  private

  def client = Autonomia::Prospecting::Research::BigDataCorpClient

  # Devolve o token, nil para tentar de novo, ou levanta.
  def attempt_token(body, attempt)
    response = @transport.post(PATH, body, {})
    status = response.code.to_i
    return retry_later(attempt, status, 'BIGDATACORP_TOKEN_RETRYABLE_HTTP') if @transport.retryable?(status) && attempt < @max_attempts
    raise client::Error.new('BIGDATACORP_TOKEN_UNAVAILABLE', phase: :token, status: status) unless status.between?(200, 299)

    token_from(response)
  rescue Timeout::Error
    raise client::Error.new('BIGDATACORP_TOKEN_UNAVAILABLE', phase: :token) unless attempt < @max_attempts

    retry_later(attempt, nil, 'BIGDATACORP_TOKEN_TIMEOUT')
  rescue *client::NETWORK_ERRORS
    raise client::Error.new('BIGDATACORP_TOKEN_UNAVAILABLE', phase: :token)
  end

  def retry_later(attempt, status, code)
    @transport.log('token_retry', :token, attempt, status, code)
    @transport.pause(attempt)
    nil
  end

  def token_from(response)
    payload = @transport.parse_json(response.body)
    access = first_present(payload, TOKEN_KEYS)
    token_id = first_present(payload, TOKEN_ID_KEYS)
    raise client::Error.new('BIGDATACORP_TOKEN_INVALID_RESPONSE', phase: :token, status: response.code.to_i) unless access && token_id

    client::Token.new(access_token: access, token_id: token_id, expires_at: @transport.now + @ttl)
  end

  def first_present(payload, keys)
    return unless payload.is_a?(Hash)

    keys.lazy.map { |key| payload[key] }.find { |value| value.is_a?(String) && value.strip.present? }&.strip
  end
end
