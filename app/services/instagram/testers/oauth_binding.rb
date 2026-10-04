class Instagram::Testers::OauthBinding
  TTL = 15.minutes

  def self.prepare(token:, account_id:, actor_id:)
    configuration = Instagram::Testers::Configuration.new(account_id: account_id)
    configuration.ensure_available!
    Instagram::Testers::RateLimiter.check!(account_id: account_id, actor_id: actor_id)
    selected = Instagram::Testers::Selection.new(account_id: account_id, actor_id: actor_id, app_id: configuration.app_id).verify(token)
    status = Instagram::Testers::Client.new(configuration: configuration).status(selected.fetch('id'))
    raise Instagram::Testers::Error, 'invalid_selection' unless status == 'accepted'

    selected
  end

  def self.claim!(payload)
    validate_payload!(payload)
    raise Instagram::Testers::Error, 'invalid_selection' unless payload['tester_installation'] == ENV.fetch('INSTAGRAM_TESTER_SESSION_NAMESPACE', '')

    selected = payload.fetch('tester_selection')
    configuration = Instagram::Testers::Configuration.new(account_id: payload.fetch('sub'))
    configuration.ensure_available!
    raise Instagram::Testers::Error, 'invalid_selection' unless configuration.app_id == selected['app_id']

    key = "instagram_testers:oauth:#{Digest::SHA256.hexdigest(payload['jti'])}"
    raise Instagram::Testers::Error, 'invalid_selection' unless Redis::Alfred.set(key, 'used', nx: true, ex: TTL.to_i * 2)
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
  end

  def self.validate_payload!(payload)
    selected = payload['tester_selection']
    valid = Instagram::Testers::Validation.target?(selected) && Instagram::Testers::Validation.id?(selected['app_id']) &&
            valid_timing?(payload) && payload['jti'].is_a?(String) && payload['jti'].length == 36
    raise Instagram::Testers::Error, 'invalid_selection' unless valid
  end

  def self.valid_timing?(payload)
    payload['exp'].is_a?(Integer) && payload['iat'].is_a?(Integer) && payload['exp'] > Time.current.to_i &&
      (payload['exp'] - payload['iat']).between?(1, TTL.to_i)
  end

  private_class_method :validate_payload!, :valid_timing?
end
