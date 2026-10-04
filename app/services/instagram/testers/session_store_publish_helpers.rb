module Instagram::Testers::SessionStorePublishHelpers
  private

  def validate_publish_input!(session, expected_version, captured_at, metadata)
    app_id = metadata.fetch(:app_id)
    business_id = metadata.fetch(:business_id)
    proxy_fingerprint = metadata.fetch(:proxy_fingerprint)
    validate_publish_session!(session)
    validate_version!(expected_version) if expected_version
    validate_publish_ids!(app_id, business_id)
    validate_publish_configuration!(app_id, business_id)
    validate_publish_admin!(session)
    validate_publish_proxy!(proxy_fingerprint)

    normalize_captured_at(captured_at, Time.current)
  rescue ArgumentError, TypeError
    raise rejected_error, cause: nil
  end

  def publish_details(session, expected_version, captured_at, metadata)
    value = Instagram::Testers::SessionSchema.normalize(session)
    validate_publish_input!(value, expected_version, captured_at, metadata)

    now = Time.current
    captured_time = normalize_captured_at(captured_at, now)
    validate_capture_order!(expected_version, captured_time)
    expires_at = [captured_time + Instagram::Testers::SessionStoreHelpers::MAX_SESSION_TTL,
                  now + Instagram::Testers::SessionStoreHelpers::MAX_SESSION_TTL].min
    raise rejected_error if expires_at <= now

    context = { value: value, expected_version: expected_version, captured_at: captured_time, now: now,
                expires_at: expires_at, metadata: metadata }
    build_publish_details(context)
  end

  def build_publish_details(context)
    version = SecureRandom.uuid
    payload_ttl = (context.fetch(:expires_at) - context.fetch(:now)).ceil
    {
      version: version,
      payload_key: payload_key(version),
      payload: build_payload(context, version),
      payload_ttl: payload_ttl,
      pointer: build_pointer(context, version),
      pointer_ttl: [payload_ttl, 1].max,
      captured_at: context.fetch(:captured_at)
    }
  end

  def build_payload(context, version)
    metadata = context.fetch(:metadata)
    {
      'version' => version,
      'session' => context.fetch(:value),
      'app_id' => metadata.fetch(:app_id).to_s,
      'business_id' => metadata.fetch(:business_id).to_s,
      'proxy_fingerprint' => metadata.fetch(:proxy_fingerprint),
      'captured_at' => context.fetch(:captured_at).utc.iso8601(6),
      'expires_at' => context.fetch(:expires_at).utc.iso8601(6)
    }
  end

  def build_pointer(context, version)
    {
      'state' => 'active',
      'version' => version,
      'updated_at' => context.fetch(:now).utc.iso8601(6),
      'captured_at' => context.fetch(:captured_at).utc.iso8601(6)
    }
  end

  def validate_publish_session!(session)
    raise rejected_error unless session && Instagram::Testers::SessionSchema.valid?(session, require_identity: true)
  end

  def validate_publish_ids!(app_id, business_id)
    raise rejected_error unless Instagram::Testers::Validation.id?(app_id.to_s)
    raise rejected_error unless Instagram::Testers::Validation.id?(business_id.to_s)
  end

  def validate_publish_configuration!(app_id, business_id)
    raise rejected_error unless app_id.to_s == @configuration.app_id.to_s
    raise rejected_error unless business_id.to_s == @configuration.business_id.to_s
  end

  def validate_publish_admin!(session)
    raise rejected_error unless session['user_id'] == expected_admin_user_id
  end

  def validate_publish_proxy!(proxy_fingerprint)
    valid = proxy_fingerprint.is_a?(String) &&
            proxy_fingerprint.match?(Instagram::Testers::SessionStoreHelpers::FINGERPRINT_FORMAT)
    raise rejected_error unless valid && proxy_fingerprint == expected_proxy_fingerprint
  end

  def normalize_captured_at(value, now)
    captured_at = captured_at_from(value)
    raise rejected_error unless captured_at

    validate_capture_window!(captured_at, now)

    captured_at
  rescue ArgumentError, TypeError
    raise rejected_error, cause: nil
  end

  def captured_at_from(value)
    case value
    when Time then value
    when DateTime then value.to_time
    when Numeric
      raise rejected_error unless value.finite?

      Time.at(value.to_f).utc
    when String then Time.iso8601(value)
    else value.to_time if value.respond_to?(:to_time)
    end
  end

  def validate_capture_window!(captured_at, now)
    raise rejected_error if captured_at > now + Instagram::Testers::SessionStoreHelpers::CLOCK_SKEW ||
                            captured_at <= now - Instagram::Testers::SessionStoreHelpers::MAX_SESSION_TTL
  end
end
