class Instagram::Testers::OauthBinding
  TTL = 15.minutes
  STATE_VERSION = 2

  # FRONTEND_URL is the configured OAuth callback base, never a request Host.
  # Require it explicitly: localhost fallback would collapse distinct installs.
  def self.installation
    uri = URI.parse(ENV.fetch('FRONTEND_URL'))
    valid = %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    raise Instagram::Testers::Error, 'meta_unavailable' unless valid

    Digest::SHA256.hexdigest("#{uri.scheme}://#{uri.host.downcase}:#{uri.port}#{uri.path.delete_suffix('/')}")
  rescue KeyError, URI::InvalidURIError
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
  end

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
    validate_selection!(payload) if payload.key?('tester_selection')
    account = authorize!(payload)

    key = "instagram:oauth:#{payload.fetch('installation')}:#{Digest::SHA256.hexdigest(payload.fetch('jti'))}"
    raise Instagram::Testers::Error, 'invalid_selection' unless Redis::Alfred.set(key, 'used', nx: true, ex: TTL.to_i * 2)

    account
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
  end

  # Reload membership and policy both before token exchange and after provider
  # requests, before writing. This uses Enterprise custom-role permissions too.
  def self.authorize!(payload)
    Account.uncached do
      account = Account.find_by(id: payload.fetch('sub'))
      raise Instagram::Testers::Error, 'forbidden' unless account&.active? && account.feature_enabled?('channel_instagram')

      membership = account.account_users.lock.find_by(user_id: payload.fetch('actor_id'))
      raise Instagram::Testers::Error, 'forbidden' unless membership

      context = { user: membership.user, account: account, account_user: membership }
      raise Instagram::Testers::Error, 'forbidden' unless InboxPolicy.new(context, Inbox).create?

      authorize_connection!(account, payload)

      account
    end
  end

  def self.authorize_connection!(account, payload)
    valid = if payload.key?('inbox_id')
              account.inboxes.exists?(id: payload.fetch('inbox_id'), channel_type: 'Channel::Instagram')
            else
              !account.feature_enabled?('instagram_assisted_onboarding') || payload.key?('tester_selection')
            end
    raise Instagram::Testers::Error, 'invalid_selection' unless valid
  end

  def self.validate_payload!(payload)
    valid = payload.is_a?(Hash) && valid_context?(payload) && valid_timing?(payload) &&
            payload['jti'].is_a?(String) && payload['jti'].length == 36 && valid_reauthorization?(payload)
    raise Instagram::Testers::Error, 'invalid_selection' unless valid
  end

  def self.valid_context?(payload)
    payload['state_version'] == STATE_VERSION && payload['installation'] == installation &&
      payload.values_at('sub', 'actor_id').all? { |id| id.is_a?(Integer) && id.positive? }
  end

  def self.validate_selection!(payload)
    selected = payload['tester_selection']
    scope = { 'account_id' => payload.fetch('sub').to_s, 'actor_id' => payload.fetch('actor_id').to_s,
              'installation' => payload.fetch('installation') }
    valid = Instagram::Testers::Validation.target?(selected) && Instagram::Testers::Validation.id?(selected['app_id']) &&
            scope.all? { |key, value| selected[key] == value }
    raise Instagram::Testers::Error, 'invalid_selection' unless valid

    configuration = Instagram::Testers::Configuration.new(account_id: payload.fetch('sub'))
    configuration.ensure_available!
    raise Instagram::Testers::Error, 'invalid_selection' unless configuration.app_id == selected['app_id']
  end

  def self.valid_reauthorization?(payload)
    return true unless payload.key?('inbox_id')

    payload['inbox_id'].is_a?(Integer) && payload['inbox_id'].positive? &&
      Instagram::Testers::Validation.id?(payload['instagram_id']) &&
      payload['return_to'] == 'inbox' && !payload.key?('tester_selection')
  end

  def self.valid_timing?(payload)
    payload['exp'].is_a?(Integer) && payload['iat'].is_a?(Integer) && payload['exp'] > Time.current.to_i &&
      payload['iat'] <= Time.current.to_i && (payload['exp'] - payload['iat']).between?(1, TTL.to_i)
  end

  private_class_method :authorize_connection!, :valid_context?, :validate_selection!, :valid_reauthorization?, :valid_timing?
end
