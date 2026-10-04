module Instagram::IntegrationHelper
  REQUIRED_SCOPES = %w[instagram_business_basic instagram_business_manage_messages].freeze

  # Generates a signed JWT token for Instagram integration
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @param actor_id [Integer] The user who is authorized to manage account inboxes
  # @param return_to [String, nil] Optional onboarding return hint
  # @return [String, nil] The bound JWT token or nil if signing/configuration fails
  def generate_instagram_token(account_id, return_to = nil, actor_id:, tester_selection: nil)
    return if client_secret.blank?

    JWT.encode(token_payload(account_id, return_to, actor_id: actor_id, tester_selection: tester_selection), client_secret, 'HS256')
  rescue StandardError
    Rails.logger.error('Instagram token generation failed')
    nil
  end

  def token_payload(account_id, return_to = nil, actor_id:, tester_selection: nil)
    payload = { sub: account_id, actor_id: actor_id, state_version: Instagram::Testers::OauthBinding::STATE_VERSION,
                installation: Instagram::Testers::OauthBinding.installation, iat: Time.current.to_i,
                exp: (Time.current + Instagram::Testers::OauthBinding::TTL).to_i, jti: SecureRandom.uuid }
    payload[:return_to] = return_to if return_to.present?
    payload[:tester_selection] = tester_selection if tester_selection
    payload
  end

  # Verifies and decodes a Instagram JWT token
  #
  # @param token [String] The JWT token to verify
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_instagram_token(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)&.dig('sub')
  end

  # Reads the onboarding return hint from a Instagram JWT token, if present.
  def instagram_token_return_to(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)&.dig('return_to')
  end

  def instagram_token_payload(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)
  end

  private

  def client_secret
    @client_secret ||= GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def decode_token(token, secret)
    payload = JWT.decode(token, secret, true, algorithm: 'HS256', verify_expiration: true).first
    Instagram::Testers::OauthBinding.validate_payload!(payload)
    payload
  rescue StandardError
    Rails.logger.error('Instagram token verification failed')
    nil
  end
end
