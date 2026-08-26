# frozen_string_literal: true

require_relative 'instrumentation'

module Vigia
  class RequestMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      started_at = Vigia::Instrumentation.current_time
      status = nil
      exception = nil

      response = @app.call(env)
      status = response.first
      response
    rescue StandardError => e
      exception = e
      raise
    ensure
      ended_at = Vigia::Instrumentation.current_time
      Vigia::Instrumentation.record_http(
        env: env,
        status: status,
        started_at: started_at,
        ended_at: ended_at,
        exception: exception
      )
    end
  end
end
