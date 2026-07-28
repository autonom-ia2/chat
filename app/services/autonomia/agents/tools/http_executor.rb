module Autonomia
  module Agents
    module Tools
      class HttpExecutor
        class Error < StandardError; end

        MAX_RESPONSE_BYTES = 256.kilobytes
        OPEN_TIMEOUT = 2
        READ_TIMEOUT = 8

        def initialize(tool:, params: {})
          @tool = tool
          @params = params.to_h.deep_stringify_keys
        end

        def call
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          body = render_body
          SafeFetch.fetch(
            rendered_url,
            method: @tool.http_method.downcase.to_sym,
            body: body,
            headers: request_headers(body),
            max_bytes: MAX_RESPONSE_BYTES,
            open_timeout: OPEN_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            allowed_content_types: %w[application/json text/plain text/html],
            allowed_content_type_prefixes: [],
            validate_content_type: false
          ) do |result|
            response = result.tempfile.read.to_s
            log_success(started_at, response.bytesize)
            return format_response(response)
          end
        rescue SafeFetch::HttpError => e
          log_failure(started_at, e.class.name)
          raise Error, "tool_http_error: #{e.message}"
        rescue SafeFetch::Error, Liquid::Error, JSON::ParserError => e
          log_failure(started_at, e.class.name)
          raise Error, "tool_execution_error: #{e.class.name.demodulize.underscore}"
        end

        private

        def rendered_url
          render_template(@tool.endpoint_url.to_s)
        end

        def render_body
          template = @tool.request_body_template.to_s
          return nil if template.blank? || @tool.http_method == 'GET'

          render_template(template)
        end

        def request_headers(body)
          headers = {}
          Array(@tool.headers_config).each do |header|
            key = header['key'].to_s
            value = header['value'].to_s
            headers[key] = render_template(value) if key.present? && value.present?
          end
          headers['Content-Type'] ||= 'application/json' if body.present?
          headers['Accept'] ||= 'application/json'
          headers
        end

        def render_template(template)
          Liquid::Template.parse(template, error_mode: :strict)
                          .render(@params, strict_variables: true, strict_filters: true)
        end

        def format_response(response)
          mapped = render_response_mapping(response)
          return mapped if mapped.present?

          parsed = JSON.parse(response)
          JSON.generate(parsed)
        rescue JSON::ParserError
          response.to_s.truncate(8_000)
        end

        def render_response_mapping(response)
          template = @tool.response_mapping.to_h['template'].to_s
          return if template.blank?

          parsed = JSON.parse(response)
          Liquid::Template.parse(template, error_mode: :strict)
                          .render({ 'response' => parsed, 'r' => parsed },
                                  strict_variables: true, strict_filters: true)
        end

        def log_success(started_at, bytes)
          Rails.logger.info(
            "[autonomia][agent_tool] account=#{@tool.account_id} agent=#{@tool.autonomia_agent_id} " \
            "tool=#{@tool.slug} status=success response_bytes=#{bytes} latency_ms=#{latency_ms(started_at)}"
          )
        end

        def log_failure(started_at, error_type)
          Rails.logger.warn(
            "[autonomia][agent_tool] account=#{@tool.account_id} agent=#{@tool.autonomia_agent_id} " \
            "tool=#{@tool.slug} status=error error_type=#{error_type} latency_ms=#{latency_ms(started_at)}"
          )
        end

        def latency_ms(started_at)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        end
      end
    end
  end
end
