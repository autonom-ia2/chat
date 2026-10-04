module Instagram::Testers::SessionStoreHelpers
  ROOT_KEY = 'instagram_testers:session'.freeze
  MAX_SESSION_TTL = 6.hours
  POINTER_TTL = MAX_SESSION_TTL.to_i
  CLOCK_SKEW = 5.minutes
  NAMESPACE_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}\z/
  VERSION_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  CODE_FORMAT = /\A[a-z0-9_]{1,64}\z/
  FINGERPRINT_FORMAT = /\A[0-9a-f]{64}\z/i

  private

  def pointer_key
    @pointer_key ||= "#{ROOT_KEY}:#{@namespace}:pointer"
  end

  def payload_key(version)
    "#{ROOT_KEY}:#{@namespace}:payload:#{version}"
  end

  def read_pointer(connection = Redis::Alfred)
    raw = connection.get(pointer_key)
    return nil if raw.blank?

    pointer = JSON.parse(raw)
    raise rejected_error unless pointer.is_a?(Hash) && valid_pointer?(pointer)

    pointer
  end

  def read_payload(version)
    raw = Redis::SecureStorage.get(payload_key(version))
    return nil if raw.blank?

    JSON.parse(raw)
  end

  def active_payload?(payload, version)
    return false unless active_payload_metadata?(payload, version)
    return false unless active_payload_time_valid?(payload)

    Instagram::Testers::SessionSchema.valid?(payload.fetch('session'), require_identity: true)
  rescue KeyError, TypeError, ArgumentError
    false
  end

  def active_payload_metadata?(payload, version)
    return false unless payload.is_a?(Hash) && payload['version'] == version
    return false unless payload['app_id'] == @configuration.app_id.to_s
    return false unless payload['business_id'] == @configuration.business_id.to_s
    return false unless payload.dig('session', 'user_id') == expected_admin_user_id

    payload['proxy_fingerprint'] == expected_proxy_fingerprint
  end

  def active_payload_time_valid?(payload)
    expires_at = Time.iso8601(payload.fetch('expires_at'))
    return false unless expires_at > Time.current

    captured_at = Time.iso8601(payload.fetch('captured_at'))
    captured_at <= Time.current + CLOCK_SKEW
  end

  def compare_and_set_pointer(expected_version, pointer, ttl: POINTER_TTL, allow_reactivation_at: nil)
    result = nil

    Redis::Alfred.with do |connection|
      connection.watch(pointer_key) do
        current = read_pointer(connection)
        matches = current&.fetch('version') == expected_version || (current.nil? && expected_version.nil?)
        matches &&= reactivation_allowed?(current, allow_reactivation_at) if pointer.fetch('state') == 'active'
        next connection.unwatch unless matches

        result = connection.multi do |transaction|
          transaction.set(pointer_key, JSON.generate(pointer), ex: ttl)
        end
      end
    end

    !result.nil?
  end

  def expected_proxy_fingerprint
    return @configuration.proxy_fingerprint if @configuration.respond_to?(:proxy_fingerprint)

    @configuration.proxy.fingerprint
  end

  def expected_admin_user_id
    return @configuration.admin_user_id.to_s if @configuration.respond_to?(:admin_user_id)

    ''
  end

  def validate_capture_order!(expected_version, captured_at)
    return unless expected_version

    pointer = read_pointer
    raise rejected_error unless pointer && pointer['version'] == expected_version

    previous_captured_at = Time.iso8601(pointer.fetch('captured_at'))
    raise rejected_error unless previous_captured_at && captured_at > previous_captured_at
  rescue KeyError, TypeError, ArgumentError
    raise rejected_error, cause: nil
  end

  def reactivation_allowed?(pointer, captured_at)
    return true unless pointer&.fetch('state') == 'invalidated'
    return false unless captured_at

    invalidated_at = Time.iso8601(pointer.fetch('invalidated_at'))
    captured_at > invalidated_at
  rescue KeyError, TypeError, ArgumentError
    false
  end

  def cleanup_payload(key)
    Redis::SecureStorage.delete(key)
  rescue StandardError
    nil
  end

  def validate_version!(version)
    raise rejected_error unless version.is_a?(String) && version.match?(VERSION_FORMAT)
  end

  def validate_code!(code)
    raise rejected_error unless code.is_a?(String) && code.match?(CODE_FORMAT)
  end

  def valid_pointer?(pointer)
    valid_pointer_metadata?(pointer) && valid_pointer_state?(pointer)
  end

  def valid_pointer_metadata?(pointer)
    pointer['state'].in?(%w[active invalidated]) && pointer['version'].is_a?(String) &&
      pointer['version'].match?(VERSION_FORMAT) && pointer['updated_at'].is_a?(String) &&
      pointer['captured_at'].is_a?(String)
  end

  def valid_pointer_state?(pointer)
    return true unless pointer['state'] == 'invalidated'

    pointer['code'].is_a?(String) && pointer['code'].match?(CODE_FORMAT) && pointer['invalidated_at'].is_a?(String)
  end
end
