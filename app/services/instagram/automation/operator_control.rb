# Dedicated, nonsecret control channel. Session and invitation storage are not cleared here.
class Instagram::Automation::OperatorControl
  ROOT_KEY = 'instagram_testers:operator'.freeze
  HEARTBEAT_TTL = 960
  REQUEST_TTL = 3600
  RUNNING_TTL = 90 # Renewed by the waiter while its child is alive; crashes cannot leave a live claim.
  MAX_BYTES = 512
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/
  STATES = %w[queued running operator_required succeeded failed].freeze
  MANAGER_STATES = %w[healthy operator_required failed].freeze
  TERMINAL_STATES = %w[operator_required failed].freeze

  class Rejected < StandardError
    def initialize
      super('operator_channel_unavailable')
    end
  end

  def initialize
    @namespace = ENV.fetch(Instagram::Testers::SessionStore::NAMESPACE_ENV, '')
  end

  def status
    value = read
    manager = value.fetch('manager')
    connectivity = manager ? manager.fetch('state') : 'unknown'
    connectivity = 'unavailable' if connectivity == 'failed'
    { manager: manager, control: value.fetch('request'), manager_connectivity: connectivity,
      operator_required: manager&.fetch('state') == 'operator_required', control_available: manager&.fetch('control_available') == true }
  rescue Rejected
    { manager: nil, control: nil, manager_connectivity: 'unknown', operator_required: false, control_available: false }
  end

  def read
    access do |connection|
      { 'type' => 'operator', 'manager' => read_value(connection, manager_key, :manager),
        'request' => read_value(connection, current_key, :request) }
    end
  end

  def heartbeat(state:, control_available:, request_id: nil)
    value = { 'state' => state, 'control_available' => control_available, 'observed_at' => timestamp(Time.current) }
    validate_value!(value, :manager)
    if request_id
      mutate do |connection|
        current = running_request!(connection, request_id)
        deadline = [Time.current + RUNNING_TTL, Time.iso8601(current.fetch('created_at')) + REQUEST_TTL].min
        current.merge('expires_at' => timestamp(deadline), 'updated_at' => timestamp(Time.current))
      end
    end
    access { |connection| connection.set(manager_key, value.to_json, ex: HEARTBEAT_TTL) }
    read
  end

  def enqueue(actor_id:, id: SecureRandom.uuid)
    raise Rejected unless uuid?(id) && valid_actor?(actor_id)

    mutate do |connection|
      manager = read_value(connection, manager_key, :manager)
      raise Rejected unless reconnect_available?(manager)

      current = read_value(connection, current_key, :request)
      next current if in_progress?(current)
      raise Rejected if current && current['id'] == id

      now = Time.current
      { 'id' => id, 'action' => 'reconnect', 'state' => 'queued', 'actor_id' => actor_id,
        'created_at' => timestamp(now), 'updated_at' => timestamp(now), 'expires_at' => timestamp(now + REQUEST_TTL) }
    end
  end

  def claim(id)
    raise Rejected unless uuid?(id)

    mutate do |connection|
      manager = read_value(connection, manager_key, :manager)
      current = read_value(connection, current_key, :request)
      raise Rejected unless reconnect_available?(manager) && current && current['id'] == id && current['state'] == 'queued'

      deadline = [Time.current + RUNNING_TTL, Time.iso8601(current.fetch('expires_at'))].min
      current.merge('state' => 'running', 'updated_at' => timestamp(Time.current),
                    'expires_at' => timestamp(deadline))
    end
  end

  def complete(id, state)
    raise Rejected unless uuid?(id) && TERMINAL_STATES.include?(state)

    mutate { |connection| running_request!(connection, id).merge('state' => state, 'updated_at' => timestamp(Time.current)) }
  end

  # SessionStore has its own WATCH/MULTI on the same reentrant Redis pool.
  # Publish outside our WATCH, then CAS the still-live claim; never nest transactions.
  def with_publication(id)
    access { |connection| running_request!(connection, id) }
    version = yield
    raise Rejected unless uuid?(version)

    mutate do |connection|
      running_request!(connection, id).merge('state' => 'succeeded', 'updated_at' => timestamp(Time.current))
    end
    version
  end

  private

  def access(&)
    raise Rejected unless Instagram::Testers::SessionStore.namespace_valid?(@namespace)

    Redis::Alfred.with(&)
  rescue Redis::BaseError, ConnectionPool::TimeoutError, JSON::ParserError, TypeError, ArgumentError
    raise Rejected, cause: nil
  end

  def mutate
    access do |connection|
      connection.watch(current_key, manager_key) do
        previous = connection.get(current_key)
        value = yield connection
        validate_value!(value, :request)
        if previous == value.to_json
          connection.unwatch
          next value
        end
        transaction = connection.multi { |writer| writer.set(current_key, value.to_json, ex: REQUEST_TTL) }
        raise Rejected unless transaction

        value
      end
    end
  end

  def running_request!(connection, id)
    raise Rejected unless uuid?(id)

    current = read_value(connection, current_key, :request)
    raise Rejected unless current && current['id'] == id && current['state'] == 'running'

    current
  end

  def read_value(connection, key, kind)
    raw = connection.get(key)
    return nil unless raw

    raise Rejected unless raw.is_a?(String) && raw.bytesize <= MAX_BYTES && connection.ttl(key).positive?

    value = JSON.parse(raw)
    validate_value!(value, kind)
    value = value.merge('state' => 'failed', 'updated_at' => value.fetch('expires_at')) if kind == :request && expired_request?(value)
    value
  end

  def validate_value!(value, kind)
    raise Rejected unless value.is_a?(Hash) && value.to_json.bytesize <= MAX_BYTES

    valid = kind == :manager ? valid_manager?(value) : valid_request?(value)
    raise Rejected unless valid
  end

  def reconnect_available?(manager)
    manager && manager['state'] == 'operator_required' && manager['control_available'] == true
  end

  def valid_manager?(value)
    value.keys.sort == %w[control_available observed_at state] && MANAGER_STATES.include?(value['state']) &&
      [true, false].include?(value['control_available']) &&
      (value['control_available'] == false || value['state'] == 'operator_required') && valid_time?(value['observed_at']) &&
      Time.iso8601(value['observed_at']).between?(Time.current - HEARTBEAT_TTL, Time.current + 5)
  end

  def valid_request?(value)
    value.keys.sort == %w[action actor_id created_at expires_at id state updated_at] && uuid?(value['id']) &&
      value['action'] == 'reconnect' && STATES.include?(value['state']) && valid_actor?(value['actor_id']) && valid_request_time?(value)
  end

  def valid_request_time?(value)
    return false unless %w[created_at expires_at updated_at].all? { |key| valid_time?(value[key]) }

    created = Time.iso8601(value['created_at'])
    expires = Time.iso8601(value['expires_at'])
    updated = Time.iso8601(value['updated_at'])
    updated.between?(created, Time.current + 5) && created <= Time.current + 5 && expires > created && expires <= created + REQUEST_TTL
  end

  def valid_actor?(value)
    value.is_a?(Integer) && value.positive? && value <= 9_007_199_254_740_991
  end

  def in_progress?(value)
    value && %w[queued running].include?(value['state'])
  end

  def expired_request?(value)
    in_progress?(value) && Time.iso8601(value.fetch('expires_at')) <= Time.current
  end

  def valid_time?(value)
    value.is_a?(String) && value.match?(TIMESTAMP) && Time.iso8601(value).utc.iso8601(3) == value
  rescue ArgumentError
    false
  end

  def uuid?(value)
    value.is_a?(String) && value.match?(UUID)
  end

  def timestamp(value)
    value.utc.iso8601(3)
  end

  def manager_key
    "#{ROOT_KEY}:#{@namespace}:manager"
  end

  def current_key
    "#{ROOT_KEY}:#{@namespace}:current"
  end
end
