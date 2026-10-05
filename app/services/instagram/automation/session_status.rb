# Read the nonsecret pointer and key metadata only; never decrypt a session.
class Instagram::Automation::SessionStatus
  include Instagram::Testers::SessionStoreHelpers

  def initialize
    @namespace = ENV.fetch(Instagram::Testers::SessionStore::NAMESPACE_ENV, '')
  end

  def call
    return result('invalid') unless Instagram::Testers::SessionStore.namespace_valid?(@namespace)

    pointer = read_pointer
    return result('missing') unless pointer

    return result('invalidated', ttl: positive_ttl(pointer_key)).merge(timestamps(pointer)) if pointer.fetch('state') == 'invalidated'

    key = payload_key(pointer.fetch('version'))
    ttls = [positive_ttl(pointer_key), positive_ttl(key)]
    return result('missing') unless ttls.all? && Redis::Alfred.exists?(key)

    result('active', present: true, ttl: ttls.min).merge(timestamps(pointer))
  rescue Instagram::Testers::Error, JSON::ParserError, KeyError, TypeError, ArgumentError
    result('invalid')
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    result('unavailable')
  end

  private

  def timestamps(pointer)
    times = { captured_at: Time.iso8601(pointer.fetch('captured_at')).utc.iso8601(6) }
    times[:published_at] = Time.iso8601(pointer.fetch('updated_at')).utc.iso8601(6) if pointer.fetch('state') == 'active'
    times
  end

  def positive_ttl(key)
    ttl = Redis::Alfred.ttl(key)
    ttl.positive? ? ttl : nil
  end

  def result(state, present: false, ttl: nil)
    { state: state, present: present, ttl: ttl }
  end

  def rejected_error
    Instagram::Testers::Error.new('session_update_rejected')
  end
end
