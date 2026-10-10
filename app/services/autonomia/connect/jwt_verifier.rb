require 'net/http'

class Autonomia::Connect::JwtVerifier
  class Unauthorized < StandardError; end

  EXPECTED_SCOPE = 'agents:provision'.freeze
  MAX_TOKEN_LIFETIME = 90.seconds
  MAX_TOKEN_BYTES = 8.kilobytes
  MAX_JWKS_BYTES = 256.kilobytes

  def initialize(
    issuer: ENV.fetch('AUTONOMIA_CONNECT_ISSUER', 'https://connect.api-autonomia.com').delete_suffix('/'),
    audience: ENV.fetch('AUTONOMIA_CONNECT_AGENTS_AUDIENCE', 'https://agents.autonomia.site/api/v1/autonomia/connect'),
    client_id: ENV.fetch('AUTONOMIA_CONNECT_CLIENT_ID', 'autonomia-connect'),
    jwks_loader: nil
  )
    @issuer = issuer
    @audience = audience
    @client_id = client_id
    @jwks_loader = jwks_loader || method(:load_remote_jwks)
  end

  def verify!(authorization_header)
    token = bearer_token(authorization_header)
    payload = decode_payload(token, signing_jwk(token))
    validate_claims!(payload)

    payload
  rescue JWT::DecodeError, JSON::ParserError, KeyError, OpenSSL::PKey::PKeyError, ArgumentError
    raise Unauthorized
  end

  private

  def bearer_token(header)
    scheme, token = header.to_s.split(' ', 2)
    raise Unauthorized unless scheme == 'Bearer' && token.present? && token.bytesize <= MAX_TOKEN_BYTES

    token
  end

  def signing_jwk(token)
    header = JWT.decode(token, nil, false).last
    raise Unauthorized unless header['alg'] == 'ES256'

    Array(@jwks_loader.call.fetch('keys')).find { |candidate| candidate['kid'] == header['kid'] }.tap do |jwk|
      raise Unauthorized if jwk.blank?
    end
  end

  def decode_payload(token, jwk)
    JWT.decode(
      token,
      JWT::JWK.import(jwk).public_key,
      true,
      algorithm: 'ES256',
      verify_iss: true,
      iss: @issuer,
      verify_aud: true,
      aud: @audience,
      verify_iat: true,
      required_claims: %w[iss sub aud scope client_id iat exp jti]
    ).first
  end

  def validate_claims!(payload)
    raise Unauthorized unless payload['scope'] == EXPECTED_SCOPE
    raise Unauthorized unless payload['client_id'] == @client_id
    raise Unauthorized unless payload['exp'].to_i - payload['iat'].to_i <= MAX_TOKEN_LIFETIME
  end

  def load_remote_jwks
    Rails.cache.fetch('autonomia-connect-jwks-v1', expires_in: 5.minutes) do
      uri = URI.parse("#{@issuer}/oauth/jwks")
      raise Unauthorized unless uri.is_a?(URI::HTTPS)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
        request = Net::HTTP::Get.new(uri.request_uri, 'Accept' => 'application/json')
        http.request(request)
      end
      raise Unauthorized unless response.is_a?(Net::HTTPSuccess)
      raise Unauthorized if response.body.bytesize > MAX_JWKS_BYTES

      JSON.parse(response.body)
    end
  rescue Timeout::Error, SocketError, SystemCallError, Net::HTTPError
    raise Unauthorized
  end
end
