# frozen_string_literal: true

require 'faraday'
require 'json'

module Vigia
  class Client
    DEFAULT_BASE_URL = 'https://vigia.api-autonomia.com'
    DEFAULT_TIMEOUT_SECONDS = 1.5

    def self.enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('VIGIA_ENABLED', false)) &&
        ENV['VIGIA_API_KEY'].present?
    end

    def self.record_execution(payload)
      return false unless enabled?

      new.record_execution(payload)
    end

    def initialize(
      base_url: ENV.fetch('VIGIA_BASE_URL', DEFAULT_BASE_URL),
      api_key: ENV.fetch('VIGIA_API_KEY', nil),
      timeout: ENV.fetch('VIGIA_TIMEOUT_SECONDS', DEFAULT_TIMEOUT_SECONDS).to_f
    )
      @base_url = base_url
      @api_key = api_key
      @timeout = timeout
    end

    def record_execution(payload)
      return false if @api_key.blank?

      response = connection.post('/v1/executions') do |request|
        request.headers['Authorization'] = "Bearer #{@api_key}"
        request.headers['Content-Type'] = 'application/json'
        request.body = payload.to_json
      end
      response.success?
    rescue StandardError => e
      log_failure(e)
      false
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.options.timeout = @timeout
        faraday.options.open_timeout = @timeout
        faraday.adapter Faraday.default_adapter
      end
    end

    def log_failure(error)
      return unless defined?(Rails)

      Rails.logger.warn("[vigia] telemetry_failed class=#{error.class.name}")
    end
  end
end
