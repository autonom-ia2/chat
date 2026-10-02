class Waha::BrazilianPhoneNumbers
  APP_NAME = 'brazilian-phone-numbers'.freeze

  class << self
    def config
      {
        strict: false,
        lookup: true,
        cache: {
          memoryTtl: '24h',
          persistent: true,
          persistentTtl: '31d'
        }
      }
    end

    def app_payload(session:, app_id:)
      {
        id: app_id,
        session: session,
        app: APP_NAME,
        enabled: true,
        config: config
      }
    end

    def desired_app(existing)
      app = existing.deep_dup
      current_config = app['config'].to_h
      current_cache = current_config['cache'].to_h

      app['enabled'] = true
      app['config'] = current_config.merge(
        'strict' => false,
        'lookup' => true,
        'cache' => current_cache.merge(
          'memoryTtl' => '24h',
          'persistent' => true,
          'persistentTtl' => '31d'
        )
      )
      app
    end
  end
end
