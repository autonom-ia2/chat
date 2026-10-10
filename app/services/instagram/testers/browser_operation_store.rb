# Keep the record schema, queue and CAS transitions in one boundary so every state
# change is validated against the same TTL and ownership rules.
# rubocop:disable Metrics/ClassLength -- the store is the single atomic operation boundary
class Instagram::Testers::BrowserOperationStore
  PREFIX = 'instagram_testers:browser_operations'.freeze
  QUEUE_KEY = "#{PREFIX}:queue".freeze
  RECORD_TTL = 5.minutes.to_i
  CLAIM_TTL = 2.minutes.to_i
  BROWSER_OPERATIONS_ENV = 'INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED'.freeze
  MAX_RECORD_BYTES = 16.kilobytes
  MAX_RESULT_BYTES = 2.megabytes
  QUEUE_SCAN_LIMIT = 32
  CLOCK_SKEW = 5.minutes
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  INSTALLATION = /\A[0-9a-f]{64}\z/
  TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/
  ACTIONS = %w[search status authorization invite].freeze
  STATES = %w[queued running ready failed expired].freeze
  TERMINAL_STATES = %w[ready failed expired].freeze

  class Rejected < StandardError
    attr_reader :code

    def initialize(code = 'meta_unavailable')
      @code = code
      super(code)
    end
  end

  class << self
    def runtime_enabled?
      Instagram::Testers::Configuration.globally_enabled? &&
        ENV.fetch(BROWSER_OPERATIONS_ENV, 'false') == 'true' &&
        ENV.fetch('INSTAGRAM_TESTER_SESSION_SOURCE', 'env') == 'managed'
    end
  end

  # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- one validated record boundary
  def enqueue(action:, account_id:, actor_id:, app_id:, installation:, request_id: nil, selection: nil, input: {},
              return_to: nil)
    require_runtime!
    validate_context!(action, account_id, actor_id, app_id, installation)
    validate_selection!(selection, action, account_id, actor_id, app_id, installation)
    validate_input!(input, action)
    validate_return_to!(return_to)

    id = SecureRandom.uuid
    request_id ||= SecureRandom.uuid
    validate_uuid!(request_id)
    now = Time.current.utc
    record = {
      'id' => id,
      'request_id' => request_id,
      'action' => action,
      'account_id' => account_id,
      'actor_id' => actor_id,
      'app_id' => app_id,
      'installation' => installation,
      'state' => 'queued',
      'created_at' => timestamp(now),
      'updated_at' => timestamp(now),
      'deadline' => timestamp(now + RECORD_TTL.seconds)
    }
    record['selection'] = selection if selection
    record['input'] = input if input.present?
    record['return_to'] = return_to if return_to.present?
    persist_new!(record)
    request_for(record)
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end
  # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

  def next_request
    require_runtime!
    ids = Redis::Alfred.with { |connection| connection.zrange(QUEUE_KEY, 0, QUEUE_SCAN_LIMIT - 1) }
    ids.each do |id|
      record = load_record(id)
      unless record
        Redis::Alfred.with { |connection| connection.zrem(QUEUE_KEY, id) }
        next
      end

      if expired?(record)
        expire!(record)
        next
      end

      next unless claimable?(record)

      return request_for(record)
    end
    nil
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end

  def claim(id:, request_id:)
    require_runtime!
    validate_uuid!(id)
    validate_uuid!(request_id)
    now = Time.current.utc
    claim_token = SecureRandom.uuid
    updated_request = compare_and_set(id) do |record|
      raise Rejected, 'invalid_selection' unless record['request_id'] == request_id
      raise Rejected, 'meta_unavailable' if expired?(record, now)
      raise Rejected, 'busy' unless claimable?(record, now)

      expires_at = [now + CLAIM_TTL.seconds, Time.iso8601(record.fetch('deadline'))].min
      updated = record.merge('state' => 'running', 'claim' => claim_token,
                             'claim_expires_at' => timestamp(expires_at), 'updated_at' => timestamp(now))
      [updated, request_for(updated, include_claim: true), false]
    end
    raise Rejected, 'busy' unless updated_request

    updated_request
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end

  def claimed(id:, request_id:, claim:)
    require_runtime!
    validate_uuid!(id)
    validate_uuid!(request_id)
    validate_uuid!(claim)
    record = load_record(id)
    raise Rejected, 'invalid_selection' unless record && record['request_id'] == request_id
    raise Rejected, 'busy' unless claimed_by?(record, claim)
    raise Rejected, 'meta_unavailable' if expired?(record)

    record
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end

  def complete(id:, request_id:, claim:, state:, result: nil, error_code: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- CAS and result fencing stay atomic
    require_runtime!
    validate_uuid!(id)
    validate_uuid!(request_id)
    validate_uuid!(claim)
    raise Rejected, 'session_update_rejected' unless TERMINAL_STATES.include?(state)

    validate_result!(result, state)
    validate_error_code!(error_code, state)

    record = claimed(id: id, request_id: request_id, claim: claim)
    ttl = remaining_ttl(record)
    raise Rejected, 'meta_unavailable' unless ttl.positive?

    persist_result!(id, claim, result, ttl) if result

    now = Time.current.utc
    completed = compare_and_set(id) do |current|
      raise Rejected, 'invalid_selection' unless current['request_id'] == request_id && claimed_by?(current, claim)
      raise Rejected, 'meta_unavailable' if expired?(current, now)

      updated = current.merge('state' => state, 'updated_at' => timestamp(now)).except('claim', 'claim_expires_at')
      updated['result_claim'] = claim if result
      updated['error_code'] = error_code if error_code
      [updated, request_for(updated), true]
    end
    raise Rejected, 'busy' unless completed

    completed
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end

  def result(id:, account_id:, actor_id:)
    require_runtime!
    validate_uuid!(id)
    record = load_record(id)
    raise Rejected, 'invalid_selection' unless record && owns?(record, account_id, actor_id)
    return public_result(record) unless expired?(record)

    expire!(record)
    current = load_record(id)
    raise Rejected, 'meta_unavailable' unless current

    public_result(current)
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Rejected, 'meta_unavailable'
  end

  private

  def require_runtime!
    raise Rejected, 'not_enabled' unless self.class.runtime_enabled?
  end

  def persist_new!(record)
    json = JSON.generate(record)
    raise Rejected, 'session_update_rejected' if json.bytesize > MAX_RECORD_BYTES

    Redis::Alfred.with do |connection|
      result = connection.multi do |transaction|
        transaction.set(record_key(record.fetch('id')), json, ex: RECORD_TTL)
        transaction.zadd(QUEUE_KEY, Time.iso8601(record.fetch('created_at')).to_f, record.fetch('id'))
      end
      raise Rejected, 'meta_unavailable' unless result
    end
  end

  def compare_and_set(id)
    result = nil
    Redis::Alfred.with do |connection|
      connection.watch(record_key(id)) do
        record = load_record(id, connection)
        raise Rejected, 'invalid_selection' unless record

        candidate = yield(record)
        next connection.unwatch unless candidate

        updated, output, remove_from_queue = candidate
        json = JSON.generate(updated)
        raise Rejected, 'session_update_rejected' if json.bytesize > MAX_RECORD_BYTES

        result = connection.multi do |transaction|
          transaction.set(record_key(id), json, xx: true, keepttl: true)
          transaction.zrem(QUEUE_KEY, id) if remove_from_queue
        end
        result = output if result
      end
    end
    result
  end

  def expire!(record)
    return unless record && TERMINAL_STATES.exclude?(record['state'])

    compare_and_set(record.fetch('id')) do |current|
      next unless current['state'] == record['state'] && expired?(current)

      now = Time.current.utc
      updated = current.merge('state' => 'expired', 'error_code' => 'meta_unavailable',
                              'updated_at' => timestamp(now)).except('claim', 'claim_expires_at')
      [updated, updated, true]
    end
  rescue Rejected
    nil
  end

  def load_record(id, connection = Redis::Alfred)
    raw = connection.get(record_key(id))
    return nil if raw.blank?

    record = JSON.parse(raw)
    validate_record!(record)
    record
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError
    raise Rejected, 'meta_unavailable'
  end

  def public_result(record)
    response = request_for(record)
    response.delete('app_id')
    return response unless record['state'] == 'ready'

    raw = Redis::SecureStorage.get(result_key(record.fetch('id'), record.fetch('result_claim')))
    raise Rejected, 'meta_unavailable' if raw.blank?

    result = JSON.parse(raw)
    raise Rejected, 'meta_unavailable' unless result.is_a?(Hash)

    response.merge(result)
  rescue Redis::SecureStorage::EncryptionNotConfigured, JSON::ParserError, TypeError
    raise Rejected, 'meta_unavailable'
  end

  def persist_result!(id, claim, result, ttl)
    json = JSON.generate(result)
    raise Rejected, 'session_update_rejected' if json.bytesize > MAX_RESULT_BYTES

    Redis::SecureStorage.set(result_key(id, claim), json, ttl)
  rescue Redis::SecureStorage::EncryptionNotConfigured
    raise Rejected, 'meta_unavailable'
  end

  def request_for(record, include_claim: false)
    request = record.slice('id', 'request_id', 'action', 'state', 'deadline', 'app_id')
    selection = record['selection']
    input = record['input']
    request['target_id'] = selection['id'] if selection
    request['username'] = selection['username'] if selection
    request['username'] = input['username'] if input
    request['claim'] = record['claim'] if include_claim && record['claim']
    request['error_code'] = record['error_code'] if record['error_code']
    request
  end

  def validate_context!(action, account_id, actor_id, app_id, installation)
    raise Rejected, 'session_update_rejected' unless ACTIONS.include?(action)
    raise Rejected, 'invalid_selection' unless positive_integer?(account_id) && positive_integer?(actor_id)
    raise Rejected, 'invalid_selection' unless Instagram::Testers::Validation.id?(app_id)
    raise Rejected, 'invalid_selection' unless installation.is_a?(String) && installation.match?(INSTALLATION)
  end

  def validate_selection!(selection, action, account_id, actor_id, app_id, installation) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity -- all selection pins are checked together
    requires_selection = %w[status authorization invite].include?(action)
    return if !requires_selection && selection.nil?
    raise Rejected, 'invalid_selection' unless requires_selection && selection.is_a?(Hash)

    valid = Instagram::Testers::Validation.target?(selection) &&
            selection.keys.sort == %w[account_id actor_id app_id id installation username] &&
            selection['account_id'] == account_id.to_s && selection['actor_id'] == actor_id.to_s &&
            selection['app_id'] == app_id && selection['installation'] == installation
    raise Rejected, 'invalid_selection' unless valid
  end

  def validate_input!(input, action)
    raise Rejected, 'session_update_rejected' unless input.is_a?(Hash)
    return if action != 'search' && input.empty?

    valid = action == 'search' && input.keys == ['username'] && Instagram::Testers::Validation.username?(input['username'])
    raise Rejected, 'invalid_username' unless valid
  end

  def validate_return_to!(return_to)
    valid = return_to.nil? || (return_to.is_a?(String) && return_to.bytesize <= 64 && !return_to.match?(/[\0-\x1f\x7f]/))
    raise Rejected, 'invalid_selection' unless valid
  end

  def validate_record!(record) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- persisted state is rejected as one schema
    required = %w[id request_id action account_id actor_id app_id installation state created_at updated_at deadline]
    raise Rejected, 'meta_unavailable' unless record.is_a?(Hash) && (required - record.keys).empty?
    raise Rejected, 'meta_unavailable' unless UUID.match?(record['id']) && UUID.match?(record['request_id'])

    validate_context!(record['action'], record['account_id'], record['actor_id'], record['app_id'], record['installation'])
    raise Rejected, 'meta_unavailable' unless STATES.include?(record['state'])

    %w[created_at updated_at deadline].each { |key| validate_timestamp!(record[key]) }
    created = Time.iso8601(record.fetch('created_at'))
    deadline = Time.iso8601(record.fetch('deadline'))
    raise Rejected, 'meta_unavailable' unless deadline > created && deadline <= created + RECORD_TTL.seconds

    validate_selection!(record['selection'], record['action'], record['account_id'], record['actor_id'], record['app_id'], record['installation'])
    validate_input!(record.fetch('input', {}), record['action'])
    validate_return_to!(record['return_to']) if record.key?('return_to')
    claim_keys = record.keys & %w[claim claim_expires_at]
    if record['state'] == 'running'
      raise Rejected, 'meta_unavailable' unless claim_keys.sort == %w[claim claim_expires_at]

      validate_uuid!(record.fetch('claim'))
      validate_timestamp!(record.fetch('claim_expires_at'))
    elsif claim_keys.any?
      raise Rejected, 'meta_unavailable'
    end
    validate_error_code!(record['error_code'], record['state']) if %w[failed expired].include?(record['state']) || record.key?('error_code')
    if record['state'] == 'ready'
      raise Rejected, 'meta_unavailable' unless record['result_claim'].is_a?(String) && UUID.match?(record['result_claim'])
    elsif record.key?('result_claim')
      raise Rejected, 'meta_unavailable'
    end
    raise Rejected, 'meta_unavailable' if JSON.generate(record).bytesize > MAX_RECORD_BYTES
  end

  def validate_result!(result, state)
    return if state == 'failed' && result.nil?
    raise Rejected, 'session_update_rejected' unless result.is_a?(Hash)
    raise Rejected, 'session_update_rejected' if JSON.generate(result).bytesize > MAX_RESULT_BYTES
  end

  def validate_error_code!(error_code, state)
    return if state == 'ready' && error_code.nil?

    valid = %w[failed expired].include?(state) && Instagram::Testers::Error::STATUSES.key?(error_code)
    raise Rejected, 'session_update_rejected' unless valid
  end

  def validate_uuid!(value)
    raise Rejected, 'invalid_selection' unless value.is_a?(String) && UUID.match?(value)
  end

  def validate_timestamp!(value)
    raise Rejected, 'meta_unavailable' unless value.is_a?(String) && TIMESTAMP.match?(value)

    Time.iso8601(value)
  rescue ArgumentError
    raise Rejected, 'meta_unavailable'
  end

  def positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end

  def owns?(record, account_id, actor_id)
    record['account_id'] == account_id.to_i && record['actor_id'] == actor_id.to_i
  end

  def claimable?(record, now = Time.current.utc)
    return true if record['state'] == 'queued'

    record['state'] == 'running' && record['claim_expires_at'].present? && Time.iso8601(record['claim_expires_at']) <= now
  rescue ArgumentError
    false
  end

  def claimed_by?(record, claim)
    record['state'] == 'running' && record['claim'] == claim &&
      record['claim_expires_at'].present? && Time.iso8601(record['claim_expires_at']) > Time.current.utc
  rescue ArgumentError
    false
  end

  def expired?(record, now = Time.current.utc)
    Time.iso8601(record.fetch('deadline')) <= now
  rescue ArgumentError, KeyError
    true
  end

  def remaining_ttl(record)
    remaining = Time.iso8601(record.fetch('deadline')) - Time.current.utc
    remaining.positive? ? remaining.to_i : 0
  rescue ArgumentError, KeyError
    0
  end

  def timestamp(time)
    time.utc.iso8601(3)
  end

  def record_key(id)
    "#{PREFIX}:record:#{id}"
  end

  def result_key(id, claim)
    "#{PREFIX}:result:#{id}:#{claim}"
  end
end
# rubocop:enable Metrics/ClassLength
