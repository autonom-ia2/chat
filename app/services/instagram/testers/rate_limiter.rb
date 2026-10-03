class Instagram::Testers::RateLimiter
  WINDOW = 60
  LIMIT = 30

  def self.check!(account_id:, actor_id:)
    key = "instagram_testers:rate:#{account_id}:#{actor_id}:#{Time.current.to_i / WINDOW}"
    results = Redis::Alfred.with do |connection|
      connection.multi do |transaction|
        transaction.incr(key)
        transaction.expire(key, WINDOW * 2)
      end
    end
    raise Instagram::Testers::Error, 'rate_limited' if results.first > LIMIT
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
  end
end
