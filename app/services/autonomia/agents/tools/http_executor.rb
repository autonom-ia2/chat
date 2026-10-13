module Autonomia
  module Agents
    module Tools
      class HttpExecutor
        # `status` (inteiro) e `trecho` (começo higienizado do corpo de um 4xx) vão em campos próprios:
        # o `Bound` repassa ao modelo só eles e a categoria, nunca o texto livre da mensagem.
        class Error < StandardError
          attr_reader :status, :trecho

          def initialize(message = nil, status: nil, trecho: nil)
            @status = status
            @trecho = trecho
            super(message)
          end
        end

        # Um valor que não pode virar requisição (corpo que deixou de ser JSON, cabeçalho com quebra de
        # linha). O nome vai para o código do erro: `tool_execution_error: <codigo>`.
        class ValorRecusado < StandardError; end

        MAX_RESPONSE_BYTES = 256.kilobytes
        OPEN_TIMEOUT = 2
        READ_TIMEOUT = 8
        # #1425: teto da transferência inteira. `open_timeout`/`read_timeout` valem por operação, e um
        # servidor que pinga um byte por vez nunca estoura nenhum dos dois. O que o prazo do SafeFetch
        # não cobre (DNS, cabeçalhos gotejando abaixo do teto por operação) está em `SafeFetch::Deadline`.
        TOTAL_TIMEOUT = 10
        # Saltos seguidos, todos na mesma origem (`cross_origin_redirects: false`).
        MAX_REDIRECTS = 3
        # O que se lê do corpo de um erro, e o que chega ao modelo depois de higienizado.
        ERROR_BODY_BYTES = 2.kilobytes
        MAX_TRECHO_DO_ERRO = 500

        def initialize(tool:, params: {})
          @tool = tool
          @params_do_modelo = params.to_h.deep_stringify_keys
        end

        def call
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          body = render_body
          headers = request_headers(body)
          SafeFetch.fetch(rendered_url, **fetch_options(body, headers)) do |result|
            response = result.tempfile.read.to_s
            log_success(started_at, response.bytesize)
            return format_response(response)
          end
        rescue ValorRecusado, SafeFetch::Error, Liquid::Error, JSON::ParserError => e
          log_failure(started_at, e.class.name)
          raise erro_da_ferramenta(e, headers)
        end

        private

        def erro_da_ferramenta(erro, headers)
          case erro
          when SafeFetch::HttpError
            Error.new("tool_http_error: #{erro.message}", status: erro.status, trecho: trecho_do_erro(erro, headers))
          when ValorRecusado then Error.new("tool_execution_error: #{erro.message}")
          else Error.new("tool_execution_error: #{erro.class.name.demodulize.underscore}")
          end
        end

        def fetch_options(body, headers)
          {
            method: @tool.http_method.downcase.to_sym,
            body: body,
            headers: headers,
            max_bytes: MAX_RESPONSE_BYTES,
            open_timeout: OPEN_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            total_timeout: TOTAL_TIMEOUT,
            max_redirects: MAX_REDIRECTS,
            cross_origin_redirects: false,
            # Defesa em profundidade: o salto para outra origem já é recusado; se um dia for seguido,
            # nenhum cabeçalho configurado vai junto.
            sensitive_headers: headers.keys,
            error_body_bytes: ERROR_BODY_BYTES,
            allowed_content_types: %w[application/json text/plain text/html],
            allowed_content_type_prefixes: [],
            validate_content_type: false
          }
        end

        def rendered_url
          render_template(@tool.endpoint_url.to_s)
        end

        # O escape do corpo, por tipo, está em `CorpoDaFerramenta` (#1425).
        def render_body
          corpo.texto
        end

        def corpo
          @corpo ||= CorpoDaFerramenta.new(tool: @tool, params: params)
        end

        # Os argumentos já no tipo do param_schema (`ParamsTipados`). Lido dentro de `call`: valor que
        # não converte é recusa tratada, como as outras.
        def params
          @params ||= ParamsTipados.converter(@params_do_modelo, @tool.param_schema)
        end

        def request_headers(body)
          headers = {}
          Array(@tool.headers_config).each do |header|
            key = header['key'].to_s
            value = header['value'].to_s
            headers[key] = header_value(render_template(value)) if key.present? && value.present?
          end
          headers['Content-Type'] ||= 'application/json' if body.present?
          headers['Accept'] ||= 'application/json'
          headers
        end

        # Quebra de linha num valor de cabeçalho abriria um cabeçalho novo. O Net::HTTP recusa com
        # ArgumentError, fora do tratamento da ferramenta; aqui vira recusa nomeada.
        def header_value(value)
          raise ValorRecusado, 'cabecalho_invalido' if value.include?("\r") || value.include?("\n")

          value
        end

        def render_template(template, global_filter: nil)
          Liquid::Template.parse(template, error_mode: :strict)
                          .render(params, strict_variables: true, strict_filters: true, global_filter: global_filter)
        end

        # Só de 4xx: é o que diz ao modelo o que o sistema recusou ("falta o CEP"). Um 5xx traz página
        # de erro e pilha, que não ajudam o modelo e podem expor o servidor.
        def trecho_do_erro(error, headers)
          return unless error.status.to_i.between?(400, 499)

          TrechoHigienizado.new(error.body_excerpt, segredos: segredos(headers), limite: MAX_TRECHO_DO_ERRO,
                                                    cortado: error.body_excerpt_truncated).to_s
        end

        # O que veio da CONFIGURAÇÃO da ferramenta, e não do modelo, e que o servidor pode ecoar no erro:
        # os valores de cabeçalho (menos os automáticos), o usuário e a senha, os pedaços do caminho e os
        # valores da query do endereço, e os valores escritos no modelo do corpo.
        def segredos(headers)
          cabecalhos = Array(headers).reject { |key, _| %w[content-type accept].include?(key.to_s.downcase) }.map(&:last)
          cabecalhos + literais_do_endereco + literais_do_corpo
        end

        # O endereço com cada {{ }} vazio: sobra só o que está escrito no cadastro.
        def literais_do_endereco
          uri = URI.parse(render_template(@tool.endpoint_url.to_s, global_filter: ->(_valor) {}))
          usuario = [uri.user, uri.password].compact.map { |parte| URI.decode_www_form_component(parte) }
          caminho = uri.path.to_s.split('/').map { |parte| URI.decode_www_form_component(parte) }
          usuario + caminho + URI.decode_www_form(uri.query.to_s).map(&:last)
        rescue URI::InvalidURIError, ArgumentError, Liquid::Error
          []
        end

        def literais_do_corpo
          corpo.literais
        rescue ValorRecusado, Liquid::Error
          []
        end

        # Sem corte aqui: quem corta é o `Bound#cabendo`, com o aviso de corte que o modelo precisa ler
        # (#1425 — antes, texto que não era JSON saía cortado em silêncio, com "...").
        # Com mapeamento, vai o que ele renderizou, MESMO VAZIO: o mapeamento existe para filtrar a
        # resposta, e cair na resposta crua entregaria ao modelo justamente o que ele tira (revisão do
        # #1425). Resposta que não é JSON não tem como ser mapeada: é erro (`parser_error`), não a crua.
        def format_response(response)
          return render_response_mapping(response) if mapping_template.present?

          JSON.generate(JSON.parse(response))
        rescue JSON::ParserError
          raise if mapping_template.present?

          response.to_s
        end

        def mapping_template
          @tool.response_mapping.to_h['template'].to_s
        end

        # Campo que a resposta não trouxe vira vazio (`strict_variables: false`): a resposta de um
        # sistema de fora muda sem aviso, e um campo a menos não pode derrubar a ferramenta. Modelo
        # com erro de sintaxe continua erro (`error_mode: :strict`, na leitura).
        def render_response_mapping(response)
          parsed = JSON.parse(response)
          Liquid::Template.parse(mapping_template, error_mode: :strict)
                          .render({ 'response' => parsed, 'r' => parsed },
                                  strict_variables: false, strict_filters: true)
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
