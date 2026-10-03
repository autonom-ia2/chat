# Parses the `signed_request` Meta posts to the deauthorize and data deletion callbacks.
# ref https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback
# Format: "<base64url HMAC-SHA256 signature>.<base64url JSON payload>", signed with the app secret.
class Instagram::SignedRequest
  ALGORITHM = 'HMAC-SHA256'.freeze

  def self.parse(signed_request, secret)
    new(signed_request, secret).payload
  end

  def initialize(signed_request, secret)
    @signed_request = signed_request.to_s
    @secret = secret
  end

  # Returns the decoded payload hash, or nil when the request is malformed or the signature does not match.
  def payload
    return if @secret.blank?

    encoded_signature, encoded_payload = @signed_request.split('.', 2)
    return if encoded_signature.blank? || encoded_payload.blank?
    return unless valid_signature?(encoded_signature, encoded_payload)

    decode_payload(encoded_payload)
  rescue ArgumentError, JSON::ParserError
    nil
  end

  private

  def decode_payload(encoded_payload)
    data = JSON.parse(Base64.urlsafe_decode64(encoded_payload))
    data if data.is_a?(Hash) && data['algorithm'].to_s.casecmp?(ALGORITHM)
  end

  def valid_signature?(encoded_signature, encoded_payload)
    expected = OpenSSL::HMAC.digest('SHA256', @secret, encoded_payload)
    ActiveSupport::SecurityUtils.secure_compare(expected, Base64.urlsafe_decode64(encoded_signature))
  end
end
