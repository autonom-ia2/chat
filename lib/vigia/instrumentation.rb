# frozen_string_literal: true

require 'net/http'
require 'securerandom'
require 'timeout'

require_relative 'client'

module Vigia
  module Instrumentation
    module_function

    TOKEN_SEGMENT = /\A[A-Za-z0-9_-]{24,}\z/
    UUID_SEGMENT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    EMAIL_SEGMENT = /@/
    MAX_STRING_ATTRIBUTE_LENGTH = 160

    def record_http(env:, status:, started_at:, ended_at:, exception: nil)
      Client.record_execution(http_payload(env:, status:, started_at:, ended_at:, exception:))
    rescue StandardError => e
      log_failure(e)
      false
    end

    def instrument_job(job)
      started_at = current_time
      exception = nil
      yield
    rescue StandardError => e
      exception = e
      raise
    ensure
      ended_at = current_time
      record_job(job:, started_at:, ended_at:, exception:)
    end

    def record_job(job:, started_at:, ended_at:, exception: nil)
      Client.record_execution(job_payload(job:, started_at:, ended_at:, exception:))
    rescue StandardError => e
      log_failure(e)
      false
    end

    def http_payload(env:, status:, started_at:, ended_at:, exception: nil)
      route = http_route(env)
      outcome = outcome_for(status, exception)
      payload = base_payload(
        operation: "#{env['REQUEST_METHOD']} #{route}",
        kind: 'http_request',
        started_at:,
        ended_at:,
        outcome:
      ).merge(
        httpMethod: env['REQUEST_METHOD'],
        httpRoute: route,
        attributes: safe_attributes(
          source: 'rails-rack-middleware',
          operationSource: route_source(env),
          requestId: request_id(env),
          projectSlug: ENV.fetch('VIGIA_PROJECT_SLUG', nil),
          environment: ENV.fetch('VIGIA_ENVIRONMENT', Rails.env)
        )
      )
      payload[:traceId] = request_id(env) if request_id(env).present?
      payload[:httpStatusCode] = status.to_i if status.present?
      attach_error!(payload, outcome, status, exception)
      payload
    end

    def job_payload(job:, started_at:, ended_at:, exception: nil)
      outcome = exception ? outcome_for(nil, exception) : 'success'
      payload = base_payload(
        operation: "job:#{job.class.name}",
        kind: 'job',
        started_at:,
        ended_at:,
        outcome:
      ).merge(
        attributes: safe_attributes(
          source: 'active-job',
          queueName: job.try(:queue_name),
          jobClass: job.class.name,
          jobId: job.try(:job_id),
          projectSlug: ENV.fetch('VIGIA_PROJECT_SLUG', nil),
          environment: ENV.fetch('VIGIA_ENVIRONMENT', Rails.env)
        )
      )
      attach_error!(payload, outcome, nil, exception)
      payload
    end

    def normalize_path(path)
      path.to_s.split('?').first.split('/').filter_map do |segment|
        next if segment.blank?

        normalize_segment(segment)
      end.then { |segments| "/#{segments.join('/')}" }
    end

    def safe_attributes(attributes)
      attributes.each_with_object({}) do |(key, value), safe|
        next unless value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

        safe[key] = value.is_a?(String) ? value.first(MAX_STRING_ATTRIBUTE_LENGTH) : value
      end
    end

    def error_class_for(status, exception)
      return 'TIMEOUT' if timeout_exception?(exception)
      return 'DATABASE' if database_exception?(exception)
      return 'RATE_LIMIT' if status.to_i == 429

      'INTERNAL'
    end

    def outcome_for(status, exception)
      return 'timeout' if timeout_exception?(exception)
      return 'failure' if exception.present?
      return 'failure' if status.to_i >= 500

      'success'
    end

    def current_time
      Time.current
    end

    def http_route(env)
      route_pattern = env['action_dispatch.route_uri_pattern']
      return route_pattern if route_pattern.present?

      normalize_path(env['PATH_INFO'])
    end

    def route_source(env)
      env['action_dispatch.route_uri_pattern'].present? ? 'route-pattern' : 'normalized-path'
    end

    def request_id(env)
      env['action_dispatch.request_id'].presence || env['HTTP_X_REQUEST_ID'].presence
    end

    def base_payload(operation:, kind:, started_at:, ended_at:, outcome:)
      {
        eventId: "cw-#{SecureRandom.uuid}",
        operation: operation.first(240),
        kind:,
        stage: ENV.fetch('VIGIA_ENVIRONMENT', Rails.env).to_s.first(160),
        startedAt: started_at.utc.iso8601(3),
        endedAt: ended_at.utc.iso8601(3),
        durationMs: duration_ms(started_at, ended_at),
        outcome:,
        occurredAt: ended_at.utc.iso8601(3)
      }
    end

    def duration_ms(started_at, ended_at)
      ((ended_at - started_at) * 1000).round
    end

    def attach_error!(payload, outcome, status, exception)
      return payload unless %w[failure timeout].include?(outcome)

      payload[:errorClass] = error_class_for(status, exception)
      payload[:errorType] = exception.class.name.first(240) if exception
      payload
    end

    def normalize_segment(segment)
      return '{id}' if segment.match?(UUID_SEGMENT)
      return '{id}' if segment.match?(/\A\d+\z/)
      return '{value}' if segment.match?(EMAIL_SEGMENT)
      return '{token}' if segment.match?(TOKEN_SEGMENT)

      segment
    end

    def timeout_exception?(exception)
      return false unless exception

      exception.is_a?(Timeout::Error) ||
        exception.is_a?(Net::OpenTimeout) ||
        exception.is_a?(Net::ReadTimeout) ||
        exception.class.name.include?('Timeout')
    end

    def database_exception?(exception)
      return false unless exception

      defined?(ActiveRecord) && exception.class.name.start_with?('ActiveRecord::')
    end

    def log_failure(error)
      Rails.logger.warn("[vigia] instrumentation_failed class=#{error.class.name}") if defined?(Rails)
    end
  end
end
