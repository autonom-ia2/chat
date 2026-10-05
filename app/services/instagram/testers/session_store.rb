class Instagram::Testers::SessionStore
  include Instagram::Testers::SessionStoreHelpers
  include Instagram::Testers::SessionStorePublishHelpers

  ROOT_KEY = Instagram::Testers::SessionStoreHelpers::ROOT_KEY
  NAMESPACE_ENV = 'INSTAGRAM_TESTER_SESSION_NAMESPACE'.freeze
  MAX_SESSION_TTL = Instagram::Testers::SessionStoreHelpers::MAX_SESSION_TTL
  POINTER_TTL = Instagram::Testers::SessionStoreHelpers::POINTER_TTL
  CLOCK_SKEW = Instagram::Testers::SessionStoreHelpers::CLOCK_SKEW
  NAMESPACE_FORMAT = Instagram::Testers::SessionStoreHelpers::NAMESPACE_FORMAT
  VERSION_FORMAT = Instagram::Testers::SessionStoreHelpers::VERSION_FORMAT
  CODE_FORMAT = Instagram::Testers::SessionStoreHelpers::CODE_FORMAT
  FINGERPRINT_FORMAT = Instagram::Testers::SessionStoreHelpers::FINGERPRINT_FORMAT

  class << self
    def namespace_valid?(value)
      value.is_a?(String) && value.match?(NAMESPACE_FORMAT)
    end
  end

  def initialize(configuration:)
    @configuration = configuration
    @namespace = ENV.fetch(NAMESPACE_ENV, '')
    raise rejected_error unless self.class.namespace_valid?(@namespace)
  end

  def current_version
    pointer = read_pointer
    pointer&.fetch('version')
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise unavailable_error, cause: nil
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError
    raise rejected_error, cause: nil
  end

  def current_snapshot
    pointer = read_pointer
    return empty_snapshot unless pointer

    version = pointer.fetch('version')
    return snapshot(session: nil, version: version) unless pointer.fetch('state') == 'active'

    payload = read_payload(version)
    return snapshot(session: nil, version: version) unless active_payload?(payload, version)

    snapshot(session: Instagram::Testers::SessionSchema.normalize(payload.fetch('session')), version: version)
  rescue Redis::SecureStorage::EncryptionNotConfigured, Redis::BaseError, ConnectionPool::TimeoutError
    raise unavailable_error, cause: nil
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError
    empty_snapshot
  end

  def publish(session:, expected_version:, captured_at:, **metadata)
    raise rejected_error unless metadata.keys.sort == %i[app_id business_id proxy_fingerprint]

    details = publish_details(session, expected_version, captured_at, metadata)
    Redis::SecureStorage.set(details[:payload_key], details[:payload], details[:payload_ttl])
    return details[:version] if compare_and_set_pointer(expected_version, details[:pointer],
                                                        ttl: details[:pointer_ttl], allow_reactivation_at: details[:captured_at])

    cleanup_payload(details[:payload_key])
    raise rejected_error
  rescue Instagram::Testers::Error
    raise
  rescue Redis::SecureStorage::EncryptionNotConfigured, Redis::BaseError, ConnectionPool::TimeoutError
    raise unavailable_error, cause: nil
  rescue StandardError
    raise rejected_error, cause: nil
  end

  def invalidate(version:, code:)
    validate_version!(version)
    validate_code!(code)
    invalidate_pointer(read_pointer, version, code)
  rescue Instagram::Testers::Error
    raise
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise unavailable_error, cause: nil
  rescue StandardError
    raise rejected_error, cause: nil
  end

  private

  def empty_snapshot
    snapshot(session: nil, version: nil)
  end

  def snapshot(session:, version:)
    { session: session, version: version }.freeze
  end

  def invalidate_pointer(pointer, version, code)
    return false unless pointer && pointer.fetch('version') == version

    invalidated_at = Time.current.utc.iso8601(6)
    # Revocation fences publishers prepared against the previous revision, regardless of capture clock skew.
    invalidated = pointer.merge('state' => 'invalidated', 'version' => SecureRandom.uuid,
                                'code' => code, 'updated_at' => invalidated_at,
                                'invalidated_at' => invalidated_at)
    compare_and_set_pointer(version, invalidated)
  end

  def rejected_error
    Instagram::Testers::Error.new('session_update_rejected')
  end

  def unavailable_error
    Instagram::Testers::Error.new('meta_unavailable')
  end
end
