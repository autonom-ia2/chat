# Only invitation locks/outcomes use this common connection. Sessions, OAuth
# state, selections and account rate limits remain in the installation Redis.
class Instagram::Testers::CoordinationRedis
  EPOCH_CHARACTERS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-'.freeze
  AOF_TIMEOUT_MS = 2000

  class << self
    def configured?
      uri = URI.parse(ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_URL', ''))
      valid_uri?(uri) && valid_epoch? && valid_ca_file?
    rescue URI::InvalidURIError
      false
    end

    def with(&)
      url = ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_URL', '')
      return Redis::Alfred.with(&) if url.blank? && !Rails.env.production?

      raise Instagram::Testers::Error, 'meta_unavailable' unless configured?

      pool(url).with do |connection|
        unless connection.get('integrity:epoch') == ENV.fetch('INSTAGRAM_TESTER_COORDINATION_EPOCH')
          raise Instagram::Testers::Error, 'meta_unavailable'
        end

        yield connection
      end
    rescue ArgumentError
      raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
    end

    def get(key)
      with { |connection| connection.get(key) }
    end

    def set(key, value, nx: false, ex: false) # rubocop:disable Naming/MethodParameterName
      with { |connection| connection.set(key, value, nx: nx, ex: ex) }
    end

    def durable_set(key, value, ex:) # rubocop:disable Naming/MethodParameterName
      with do |connection|
        next false unless connection.set(key, value, nx: true, ex: ex)

        # WAITAOF tracks preceding writes on this exact physical connection.
        local_fsync, = connection.redis.call(['WAITAOF', 1, 0, AOF_TIMEOUT_MS])
        raise Instagram::Testers::Error, 'invite_unknown' unless local_fsync >= 1

        true
      end
    rescue Redis::BaseError, ConnectionPool::TimeoutError
      raise Instagram::Testers::Error.new('invite_unknown'), cause: nil
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

      valid_database_path?(uri.path)
    end

    def valid_database_path?(path)
      path.blank? || (path.start_with?('/') && path.length.between?(2, 4) && path.delete_prefix('/').delete('0123456789').empty?)
    end

    def valid_epoch?
      epoch = ENV.fetch('INSTAGRAM_TESTER_COORDINATION_EPOCH', '')
      epoch.ascii_only? && epoch.bytesize.between?(16, 128) && epoch.delete(EPOCH_CHARACTERS).empty?
    end

    def valid_ca_file?
      path = ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE', '')
      path.empty? || (Pathname.new(path).absolute? && File.lstat(path).file?)
    rescue SystemCallError, ArgumentError
      false
    end

    def pool(url)
      ssl_params = { verify_mode: OpenSSL::SSL::VERIFY_PEER }
      ca_file = ENV.fetch('INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE', '')
      ssl_params[:ca_file] = ca_file unless ca_file.empty?
      options = { url: url, timeout: 2, reconnect_attempts: 0, ssl_params: ssl_params }
      fingerprint = Digest::SHA256.hexdigest(Marshal.dump(options))
      @pools ||= {}
      @pool_mutex ||= Mutex.new
      @pool_mutex.synchronize do
        @pools[fingerprint] ||= ConnectionPool.new(size: 5, timeout: 1) do
          Redis::Namespace.new('instagram_tester_coordination', redis: Redis.new(**options))
        end
      end
    end
  end
end
