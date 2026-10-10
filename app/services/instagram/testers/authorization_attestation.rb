class Instagram::Testers::AuthorizationAttestation
  TTL = 5.minutes
  MAX_TOKEN_BYTES = 4096
  PURPOSE = 'instagram_tester_authorization_attestation'.freeze
  KEY_PREFIX = 'instagram_testers:authorization_attestation'.freeze
  ACTIONS = %w[status invite].freeze
  SCOPE_KEYS = %w[account_id actor_id app_id id installation username].freeze
  PAYLOAD_KEYS = (SCOPE_KEYS + %w[status source_action operation_id request_id attested_at]).freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  INSTALLATION = /\A[0-9a-f]{64}\z/
  TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/

  class << self
    def issue(selection:, operation_id:, request_id:, source_action:, attested_at: Time.current.utc)
      payload = selection.slice(*SCOPE_KEYS).merge(
        'status' => 'accepted',
        'source_action' => source_action,
        'operation_id' => operation_id,
        'request_id' => request_id,
        'attested_at' => attested_at.utc.iso8601(6)
      )
      validate_payload!(payload)
      raise Instagram::Testers::Error, 'invalid_selection' unless current_installation?(payload)

      verifier.generate(payload, expires_in: TTL, purpose: PURPOSE)
    rescue NoMethodError, TypeError
      raise Instagram::Testers::Error, 'invalid_selection'
    end

    def consume!(token:, selection:)
      payload = verified_payload(token)
      valid = current_installation?(payload) && valid_selection?(selection) &&
              payload.slice(*SCOPE_KEYS) == selection.slice(*SCOPE_KEYS)
      raise Instagram::Testers::Error, 'invalid_selection' unless valid

      key = key_for(payload)
      acquired = Redis::Alfred.set(key, 'used', nx: true, ex: TTL.to_i)
      raise Instagram::Testers::Error, 'unknown_status' unless acquired

      payload
    rescue Redis::BaseError, ConnectionPool::TimeoutError
      raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
    rescue NoMethodError, TypeError
      raise Instagram::Testers::Error, 'invalid_selection'
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def verified_payload(token)
      raise Instagram::Testers::Error, 'unknown_status' unless token.is_a?(String) && token.bytesize.between?(1, MAX_TOKEN_BYTES)

      payload = verifier.verified(token, purpose: PURPOSE)
      validate_payload!(payload)
      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError, Instagram::Testers::Error
      raise Instagram::Testers::Error, 'unknown_status'
    end

    def validate_payload!(payload)
      valid = valid_payload_shape?(payload) && valid_operation_scope?(payload) && valid_selection?(payload.slice(*SCOPE_KEYS))
      raise Instagram::Testers::Error, 'invalid_selection' unless valid

      Time.iso8601(payload.fetch('attested_at'))
    rescue ArgumentError, KeyError, TypeError
      raise Instagram::Testers::Error, 'invalid_selection'
    end

    def valid_payload_shape?(payload)
      payload.is_a?(Hash) && payload.keys.sort == PAYLOAD_KEYS.sort && payload['status'] == 'accepted' &&
        ACTIONS.include?(payload['source_action']) && TIMESTAMP.match?(payload['attested_at'])
    end

    def valid_operation_scope?(payload)
      UUID.match?(payload['operation_id']) && UUID.match?(payload['request_id'])
    end

    def valid_selection?(selection)
      valid_selection_shape?(selection) && valid_selection_ids?(selection)
    end

    def valid_selection_shape?(selection)
      selection.is_a?(Hash) && selection.keys.sort == SCOPE_KEYS.sort && Instagram::Testers::Validation.target?(selection)
    end

    def valid_selection_ids?(selection)
      Instagram::Testers::Validation.id?(selection['account_id']) &&
        Instagram::Testers::Validation.id?(selection['actor_id']) &&
        Instagram::Testers::Validation.id?(selection['app_id']) &&
        selection['installation'].is_a?(String) && INSTALLATION.match?(selection['installation'])
    end

    def current_installation?(payload)
      payload['installation'] == Instagram::Testers::OauthBinding.installation
    end

    def key_for(payload)
      [KEY_PREFIX, payload.fetch('installation'), payload.fetch('operation_id'), payload.fetch('request_id')].join(':')
    end
  end
end
