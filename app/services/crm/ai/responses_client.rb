require 'ipaddr'
require 'resolv'

module Crm
  module Ai
    class ResponsesClient
      class Error < StandardError; end

      # feature/account/pipeline são OPCIONAIS e só servem à telemetria de consumo (Gestão IA):
      # quando ambos feature+account estão presentes, cada chamada bem-sucedida grava 1 evento de uso
      # (só metadados — nunca prompt/resposta). Sem eles, comportamento idêntico ao anterior.
      # cache_key_scope controla SÓ a etiqueta de roteamento de cache (prompt_cache_key), não a
      # telemetria nem o conteúdo. :account (padrão) isola por conta (multi-tenant). :feature usa só a
      # feature — válido quando o prefixo (instructions) é conta-agnóstico (ex.: classify), consolidando
      # o roteamento entre contas p/ subir o hit-rate global do mesmo prefixo.
      def initialize(credential:, feature: nil, account: nil, pipeline: nil, cache_key_scope: :account)
        @credential = credential
        @feature = feature
        @account = account
        @pipeline = pipeline
        @cache_key_scope = cache_key_scope
      end

      def create(model:, instructions:, input:, schema: nil, reasoning_effort: 'low', tools: nil, timeout: 120)
        body = base_body(model, instructions, input, schema, reasoning_effort, tools).merge(store: false)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = post_responses(body, timeout: timeout, operation: 'responses.create', started_at: started_at)
        parse_response(response, model: model, requested_tools: tools, started_at: started_at, reasoning_effort: reasoning_effort)
      end

      # Single-step custom tool loop for Autonom.ia agents. The first response may request one
      # or more `function_call` items; the caller executes them server-side and returns compact
      # outputs. We then ask the model for the final structured answer without offering another
      # custom-tool round, keeping the MVP bounded and predictable.
      def create_with_tool_executor(model:, instructions:, input:, schema:, reasoning_effort: 'low', tools: nil,
                                    timeout: 120)
        return create(model: model, instructions: instructions, input: input, schema: schema,
                      reasoning_effort: reasoning_effort, tools: tools, timeout: timeout) unless block_given? && tools.present?

        first_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        first_body = base_body(model, instructions, input, schema, reasoning_effort, tools).merge(store: false)
        first_response = post_responses(first_body, timeout: timeout, operation: 'responses.create',
                                                    started_at: first_started_at)
        first_payload = parse_raw(first_response, operation: 'responses.create', model: model,
                                                  started_at: first_started_at)
        first_used = tools_used(first_payload)
        log_call(model, tools, first_used, first_started_at)
        record_usage(first_payload['usage'], model, reasoning_effort, first_started_at)

        calls = function_calls(first_payload)
        return parse_response_payload(first_payload, model: model, requested_tools: tools, started_at: first_started_at,
                                                     reasoning_effort: reasoning_effort) if calls.empty?

        tool_outputs = yield(calls)
        second_input = normalize_input(input) + Array(first_payload['output']) + Array(tool_outputs)
        second_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        second_body = base_body(model, instructions, second_input, schema, reasoning_effort, nil).merge(store: false)
        second_response = post_responses(second_body, timeout: timeout, operation: 'responses.create.tool_result',
                                                      started_at: second_started_at)
        result = parse_response(second_response, model: model, requested_tools: tools,
                                                 started_at: second_started_at, reasoning_effort: reasoning_effort)
        result[:tools_used] = (Array(result[:tools_used]) + first_used).uniq
        result
      end

      # Background mode: a OpenAI aceita o pedido e processa do lado dela; retorna na hora um
      # response_id que buscamos depois com retrieve. EXIGE store:true (a resposta fica retida
      # p/ ser recuperada). Usado pela geração de e-mail (operação de vários minutos).
      def create_background(model:, instructions:, input:, schema: nil, reasoning_effort: 'low', tools: nil)
        body = base_body(model, instructions, input, schema, reasoning_effort, tools).merge(store: true, background: true)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = post_responses(body, timeout: 120, operation: 'responses.create_background', started_at: started_at)
        payload = parse_raw(response, operation: 'responses.create_background', model: model, started_at: started_at)
        { id: payload['id'], status: payload['status'] }
      end

      # Consulta o estado de um pedido em background. status ∈ queued/in_progress/completed/
      # failed/incomplete/cancelled. Quando completed devolve o texto; senão devolve o erro.
      def retrieve(response_id)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = with_timeout_guard(operation: 'responses.retrieve', response_id: response_id, started_at: started_at) do
          HTTParty.get("#{api_base}/v1/responses/#{response_id}", headers: auth_headers, timeout: 30)
        end
        payload = parse_raw(response, operation: 'responses.retrieve', response_id: response_id, started_at: started_at)
        {
          status: payload['status'],
          text: payload['output_text'].presence || extract_output_text(payload),
          usage: payload['usage'] || {},
          error: payload.dig('error', 'message') || payload.dig('incomplete_details', 'reason')
        }
      end

      # Best-effort: apaga a resposta retida na OpenAI após persistirmos (minimiza retenção).
      def delete(response_id)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        with_timeout_guard(operation: 'responses.delete', response_id: response_id, started_at: started_at) do
          HTTParty.delete("#{api_base}/v1/responses/#{response_id}", headers: auth_headers, timeout: 30)
        end
        true
      rescue Error => e
        log_exception('responses.delete', e, response_id: response_id, started_at: started_at)
        false
      end

      private

      def base_body(model, instructions, input, schema, reasoning_effort, tools = nil)
        body = {
          model: model,
          instructions: instructions,
          input: normalize_input(input),
          reasoning: { effort: reasoning_effort }
        }
        key = prompt_cache_key
        body[:prompt_cache_key] = key if key.present?
        body[:text] = structured_text_format(schema) if schema.present?
        body[:tools] = tools if tools.present?
        body
      end

      # Etiqueta de roteamento de cache da OpenAI: pedidos com a mesma chave tendem ao mesmo backend,
      # elevando o hit-rate do prefixo estável (instructions). Derivada de feature:account — isola por
      # conta (multi-tenant) p/ uma conta de alto volume não degradar o roteamento das outras. Só
      # metadado de roteamento — NUNCA contém conteúdo/credencial. Ausente quando não há feature
      # (caching automático ≥1024 tok segue valendo, só sem o ganho de roteamento).
      def prompt_cache_key
        return if @feature.blank?
        return @feature.to_s if @cache_key_scope == :feature

        @account.present? ? "#{@feature}:#{@account.id}" : @feature.to_s
      end

      def auth_headers
        { 'Authorization' => "Bearer #{@credential[:api_key]}", 'Content-Type' => 'application/json' }
      end

      def post_responses(body, timeout:, operation:, started_at:)
        with_timeout_guard(operation: operation, model: body[:model], started_at: started_at) do
          HTTParty.post("#{api_base}/v1/responses", headers: auth_headers, body: body.to_json, timeout: timeout)
        end
      rescue Error => e
        log_exception(operation, e, model: body[:model], started_at: started_at) unless e.message.start_with?('network_timeout:')
        raise
      end

      # Encapsula timeouts de rede como Error (antes vazavam como Net::ReadTimeout → HTTP 500 cru
      # no controller, que só rescue-ava Error). Agora o chamador trata graciosamente.
      def with_timeout_guard(operation: nil, model: nil, response_id: nil, started_at: nil)
        yield
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
        log_exception(operation || 'openai.request', e, model: model, response_id: response_id, started_at: started_at)
        raise Error, "network_timeout: #{e.class.name.demodulize.underscore}"
      end

      def parse_raw(response, operation: 'openai.request', model: nil, response_id: nil, started_at: nil)
        unless response.success?
          log_http_error(response, operation: operation, model: model, response_id: response_id, started_at: started_at)
          raise Error, extract_error_message(response)
        end

        response.parsed_response
      end

      # Back-compat: String callers (followup/summary/classify/rewrite) keep working — a plain
      # string is wrapped as a single user text part. Arrays (multimodal content parts / messages)
      # are passed through untouched.
      def normalize_input(input)
        return input unless input.is_a?(String)

        [{ role: 'user', content: [{ type: 'input_text', text: input }] }]
      end

      def api_base
        base = (@credential[:api_base].presence || 'https://api.openai.com').to_s.strip.chomp('/')
        validate_api_base!(base)
        base
      end

      # Delega ao guard SSRF compartilhado (fonte única; usado também pelo EmbeddingService).
      # Preserva o contrato externo: levanta Crm::Ai::ResponsesClient::Error 'invalid_api_base'.
      def validate_api_base!(base)
        ::Crm::Ai::ApiBaseGuard.validate!(base)
      rescue ::Crm::Ai::ApiBaseGuard::BlockedError
        raise Error, 'invalid_api_base'
      end

      def structured_text_format(schema)
        {
          format: {
            type: 'json_schema',
            name: schema[:name] || 'crm_ai_response',
            strict: true,
            schema: schema[:schema]
          }
        }
      end

      def parse_response(response, model: nil, requested_tools: nil, started_at: nil, reasoning_effort: nil)
        unless response.success?
          log_http_error(response, operation: 'responses.create', model: model, started_at: started_at)
          raise Error, extract_error_message(response)
        end

        parse_response_payload(response.parsed_response, model: model, requested_tools: requested_tools,
                                                        started_at: started_at, reasoning_effort: reasoning_effort)
      end

      def parse_response_payload(payload, model: nil, requested_tools: nil, started_at: nil, reasoning_effort: nil)
        text = payload['output_text'].presence || extract_output_text(payload)
        if text.blank?
          log_failure(
            'responses.create',
            model: model,
            response_id: payload['id'],
            error_code: 'empty_response',
            error_message: 'empty_response',
            started_at: started_at
          )
          raise Error, 'empty_response'
        end

        used = tools_used(payload)
        log_call(model, requested_tools, used, started_at)
        record_usage(payload['usage'], model, reasoning_effort, started_at)
        {
          text: text,
          usage: payload['usage'] || {},
          response_id: payload['id'],
          tools_used: used
        }
      end

      def function_calls(payload)
        Array(payload['output']).select { |item| item['type'] == 'function_call' }
      end

      # Telemetria de consumo (Gestão IA). Só dispara quando o cliente foi construído com
      # feature+account; o próprio UsageRecorder é best-effort e nunca levanta.
      def record_usage(usage, model, reasoning_effort, started_at)
        return if @feature.blank? || @account.blank?

        latency = started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round : nil
        UsageRecorder.record(
          account: @account, feature: @feature, model: model, usage: usage,
          reasoning_effort: reasoning_effort, latency_ms: latency, pipeline: @pipeline
        )
      end

      # Tipos de item de output que representam uso de ferramenta (sufixo _call). SÓ metadados —
      # nunca conteúdo/args. Ex.: web_search_call → web_search, file_search_call → file_search.
      def tools_used(payload)
        Array(payload['output']).filter_map do |item|
          type = item['type'].to_s
          type.delete_suffix('_call') if type.end_with?('_call')
        end.uniq
      end

      # 1 log por chamada: modelo, tools pedidas, tools usadas, latência. NUNCA prompt/conteúdo/
      # credencial (só metadados — auditoria de uso de web_search etc.).
      def log_call(model, requested_tools, used, started_at)
        latency = started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round : nil
        requested = Array(requested_tools).filter_map { |t| t.is_a?(Hash) ? (t[:type] || t['type']) : t }
        Rails.logger.info(
          "[crm][ai][responses] model=#{model} tools_requested=#{requested.join(',')} " \
          "tools_used=#{used.join(',')} latency_ms=#{latency}"
        )
      end

      def log_http_error(response, operation:, model: nil, response_id: nil, started_at: nil)
        parsed = safe_parsed_response(response)
        error = parsed.is_a?(Hash) ? parsed['error'] : nil
        log_failure(
          operation,
          model: model,
          response_id: response_id,
          status: response.code,
          request_id: response.headers['x-request-id'] || response.headers['openai-request-id'],
          error_code: error.is_a?(Hash) ? error['code'] : nil,
          error_type: error.is_a?(Hash) ? error['type'] : nil,
          error_message: extract_error_message(response),
          started_at: started_at
        )
      end

      def log_exception(operation, exception, model: nil, response_id: nil, started_at: nil)
        log_failure(
          operation,
          model: model,
          response_id: response_id,
          error_type: exception.class.name,
          error_message: exception.message,
          started_at: started_at
        )
      end

      # Loga somente metadados operacionais. Nunca prompt, input, output, headers de auth
      # nem corpo bruto da resposta, pois podem conter dados do cliente.
      def log_failure(operation, model: nil, response_id: nil, status: nil, request_id: nil,
                      error_code: nil, error_type: nil, error_message: nil, started_at: nil)
        latency = started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round : nil
        Rails.logger.error(
          "[crm][ai][openai_error] operation=#{operation} model=#{model} status=#{status} " \
          "error_code=#{error_code} error_type=#{error_type} request_id=#{request_id} " \
          "response_id=#{response_id} credential_source=#{@credential[:source]} api_host=#{api_host} " \
          "latency_ms=#{latency} message=#{error_message.to_s.truncate(300)}"
        )
      end

      def safe_parsed_response(response)
        response.parsed_response
      rescue StandardError
        nil
      end

      def api_host
        URI.parse(api_base).host
      rescue StandardError
        nil
      end

      def extract_output_text(payload)
        Array(payload['output']).flat_map do |item|
          next [] unless item['type'] == 'message'

          Array(item['content']).filter_map do |part|
            part['text'] if part['type'] == 'output_text'
          end
        end.join("\n").presence
      end

      def extract_error_message(response)
        parsed = safe_parsed_response(response)
        return parsed['error']['message'] if parsed.is_a?(Hash) && parsed.dig('error', 'message').present?

        "openai_responses_error_#{response.code}"
      end
    end
  end
end
