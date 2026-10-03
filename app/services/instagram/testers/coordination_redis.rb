# Only invitation locks/outcomes use this common connection. Sessions, OAuth
# state, selections and account rate limits remain in the installation Redis.
class Instagram::Testers::CoordinationRedis
  class << self
    def configured?
      uri = URI.parse(ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_URL', ''))
      valid_uri?(uri)
    rescue URI::InvalidURIError
      false
    end

    def with(&)
      url = ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_URL', '')
      return Redis::Alfred.with(&) if url.blank? && !Rails.env.production?

      raise Instagram::Testers::Error, 'meta_unavailable' unless configured?

      pool(url).with(&)
    rescue ArgumentError
      raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
    end

    def get(key)
      with { |connection| connection.get(key) }
    end

    def set(key, value, nx: false, ex: false) # rubocop:disable Naming/MethodParameterName
      with { |connection| connection.set(key, value, nx: nx, ex: ex) }
    end

    def delete_if_equals(key, expected_value)
      with do |connection|
        connection.watch(key) do
          next connection.unwatch unless connection.get(key) == expected_value

          connection.multi { |transaction| transaction.del(key) }
        end
      end
    end

    private

    def valid_uri?(uri)
      return false unless uri.scheme == 'rediss'
      return false unless uri.host.present? && uri.password.present?
      return false unless uri.fragment.nil? && uri.query.nil?

      uri.path.blank? || uri.path.match?(%r{\A/[0-9]{1,3}\z})
    end

    def pool(url)
      fingerprint = Digest::SHA256.hexdigest(url)
      @pools ||= {}
      @pool_mutex ||= Mutex.new
      @pool_mutex.synchronize do
        @pools[fingerprint] ||= ConnectionPool.new(size: 5, timeout: 1) do
          Redis::Namespace.new('instagram_tester_coordination', redis: Redis.new(url: url, timeout: 2, reconnect_attempts: 0,
                                                                                 ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER }))
        end
      end
    end
  end
end
