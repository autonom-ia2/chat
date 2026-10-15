require 'uri'

module Waha
  # Cliente HTTP fino do motor externo (WAHA). Autentica via X-Api-Key. Levanta
  # Waha::Client::Error em qualquer falha, com status + corpo para diagnóstico.
  class Client
    # status: o código HTTP quando a WAHA respondeu; nil quando não houve resposta (conexão, timeout).
    class Error < StandardError
      attr_reader :status

      def initialize(message = nil, status: nil)
        super(message)
        @status = status
      end
    end

    # A resposta não chegou: não dá para saber se o motor executou o pedido.
    class Timeout < Error; end
    # O recurso não existe no motor (ex.: sessão já apagada).
    class NotFound < Error; end

    DEFAULT_TIMEOUT = 20

    def initialize(config: Waha::Config)
      @base = config.api_url
      @key = config.api_key
    end

    # ---- SESSÕES ----
    def create_session(name, start: true, config: {}, apps: nil)
      payload = { name: name, start: start, config: config }
      payload[:apps] = apps if apps.present?
      post('/api/sessions', payload)
    end

    def get_session(name, timeout: DEFAULT_TIMEOUT)
      get("/api/sessions/#{name}", timeout: timeout)
    end

    # Sem `apps`, a chave não vai no corpo e o motor mantém os apps da sessão (verificado no motor em 14/10/2026).
    # `apps: nil` também omite: null no JSON não é um pedido seguro.
    def update_session(name, config:, apps: nil)
      body = { config: config }
      body[:apps] = apps unless apps.nil?
      put("/api/sessions/#{name}", body)
    end

    def list_sessions(all: true)
      get("/api/sessions?all=#{all}")
    end

    def start_session(name)
      post("/api/sessions/#{name}/start")
    end

    def restart_session(name)
      post("/api/sessions/#{name}/restart")
    end

    def logout_session(name)
      post("/api/sessions/#{name}/logout")
    end

    def delete_session(name)
      delete("/api/sessions/#{name}")
    end

    # QR como valor cru (string) — { "value": "..." }. O proxy de imagem fica no controller.
    def qr_value(name)
      get("/api/#{name}/auth/qr?format=raw")
    end

    # QR como bytes PNG (para o controller repassar como imagem).
    def qr_image(name)
      raw_get("/api/#{name}/auth/qr")
    end

    # Código de pareamento (alternativa ao QR): o celular digita o código em "Conectar com número de telefone".
    def request_pairing_code(name, phone:)
      post("/api/#{name}/auth/request-code", { phoneNumber: phone })
    end

    # Limite de conversas novas do número no ciclo atual (WhatsApp Híbrido, chat#1067).
    def capping(session)
      get("/api/sessions/#{session}/capping")
    end

    # Limite temporário de conversas novas pelos aparelhos conectados (WhatsApp Híbrido, chat#1480).
    # Só informativo na aba: timeout curto para não segurar a tela.
    TIMELOCK_TIMEOUT = 5

    def timelock(session)
      get("/api/sessions/#{session}/timelock", timeout: TIMELOCK_TIMEOUT)
    end

    # "digitando…" antes do envio (WhatsApp Híbrido, chat#1067).
    def start_typing(session:, chat_id:, timeout: DEFAULT_TIMEOUT)
      post('/api/startTyping', { session: session, chatId: chat_id }, timeout: timeout)
    end

    def stop_typing(session:, chat_id:, timeout: DEFAULT_TIMEOUT)
      post('/api/stopTyping', { session: session, chatId: chat_id }, timeout: timeout)
    end

    # ---- ENVIO DIRETO (WhatsApp Híbrido, chat#1067) ----
    # O id é gerado antes do envio para a mensagem já ter identidade quando o eco da Meta chegar.
    def new_message_id(session)
      get("/api/#{session}/new-message-id")['id']
    end

    def send_text(session:, chat_id:, text:, id:)
      post('/api/sendText', { session: session, chatId: chat_id, text: text, id: id })
    end

    # kind: sendImage | sendFile | sendVoice | sendVideo. media: { file: { url:, mimetype:, filename: }, caption: }
    def send_media(kind, session:, chat_id:, id:, media:)
      body = { session: session, chatId: chat_id, file: media[:file], id: id }
      body[:caption] = media[:caption] if media[:caption].present?
      body[:convert] = true if %w[sendVoice sendVideo].include?(kind)
      post("/api/#{kind}", body)
    end

    # Uma mensagem guardada pelo motor, pelo id simples do WhatsApp (chat#1489). O GOWS guarda as recebidas: comprovado
    # em produção no spike de 15/10/2026 (6/6, a mais antiga com 7 dias). Sem mídia: só o texto e os metadados.
    GET_MESSAGE_TIMEOUT = 10

    def get_message(session, chat_id, id, download_media: false)
      get("/api/#{session}/chats/#{chat_id}/messages/#{id}?downloadMedia=#{download_media}", timeout: GET_MESSAGE_TIMEOUT)
    end

    # ---- APPS (conector de mensagens) ----
    def create_app(session:, app_id:, config:, app: 'chatwoot')
      post('/api/apps', { id: app_id, session: session, app: app, enabled: true, config: config })
    end

    def list_apps(session)
      get("/api/apps?session=#{session}")
    end

    def get_app(app_id)
      get("/api/apps/#{app_id}")
    end

    def update_app(app_id, app)
      put("/api/apps/#{app_id}", app)
    end

    def delete_app(app_id)
      delete("/api/apps/#{app_id}")
    end

    # timeout: segundos de espera desta consulta (quem chama dentro de um lote, como o cron de avisos, usa menos).
    def check_contact_exists(phone:, session:, timeout: DEFAULT_TIMEOUT)
      query = URI.encode_www_form(phone: phone, session: session)
      get("/api/contacts/check-exists?#{query}", timeout: timeout)
    end

    # Read-only capability probe. When the module is enabled but no App is configured
    # for the session, WAHA returns a structured 404 saying the App is not enabled.
    # When the module itself is disabled, Nest returns "Cannot GET ..." instead.
    def brazilian_phone_numbers_available?(session)
      path = "/api/apps/brazilian-phone-numbers/#{URI.encode_www_form_component(session)}/cache/stats"
      response = HTTParty.get("#{@base}#{path}", headers: headers, timeout: DEFAULT_TIMEOUT)
      return true if response.success? || response.code == 422
      return brazilian_phone_numbers_route_present?(response) if response.code == 404

      raise Error, "WAHA GET #{path} -> #{response.code}"
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      raise Error, "WAHA GET #{path} falhou: #{e.class}"
    end

    private

    def brazilian_phone_numbers_route_present?(response)
      body = response.parsed_response
      message = body.is_a?(Hash) ? body['message'].to_s : response.body.to_s
      message.include?("App 'brazilian-phone-numbers' is not enabled for session")
    end

    def headers
      { 'X-Api-Key' => @key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    end

    def post(path, body = nil, timeout: DEFAULT_TIMEOUT)
      request(:post, path, body, timeout: timeout)
    end

    def get(path, timeout: DEFAULT_TIMEOUT)
      request(:get, path, timeout: timeout)
    end

    def put(path, body)
      request(:put, path, body)
    end

    def delete(path)
      request(:delete, path)
    end

    def request(method, path, body = nil, timeout: DEFAULT_TIMEOUT)
      response = HTTParty.public_send(
        method, "#{@base}#{path}",
        headers: headers, body: body.nil? ? nil : body.to_json, timeout: timeout
      )
      unless response.success?
        error_class = response.code == 404 ? NotFound : Error
        raise error_class.new("WAHA #{method.upcase} #{path} -> #{error_detail(response, body)}", status: response.code)
      end

      response.parsed_response
    rescue JSON::ParserError
      # A mensagem do erro de JSON traz um pedaço do corpo (pode ter credencial): só a classe.
      raise Error, "WAHA #{method.upcase} #{path} resposta inválida (JSON::ParserError)"
    rescue Net::ReadTimeout => e
      raise Timeout, "WAHA #{method.upcase} #{path} sem resposta: #{scrub(e.message, body)}"
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Errno::ECONNREFUSED => e
      raise Error, "WAHA #{method.upcase} #{path} falhou: #{scrub(e.message, body)}"
    end

    def error_detail(response, body)
      scrub(scrub("#{response.code}: #{response.body.to_s[0, 300]}", body), parsed_or_nil(response))
    end

    def parsed_or_nil(response)
      response.parsed_response
    rescue StandardError
      nil
    end

    # A credencial do proxy da sessão (#1516) vai no corpo do pedido e volta em claro nas respostas do motor: se aparecer
    # num erro (pedido ou resposta), não chega ao log.
    def scrub(text, body)
      proxy = body.is_a?(Hash) ? body.with_indifferent_access.dig(:config, :proxy) : nil
      secrets = proxy.is_a?(Hash) ? proxy.values_at(:password, :username).compact_blank.map(&:to_s) : []
      secrets.reduce(text.to_s) { |scrubbed, secret| scrubbed.gsub(secret, '[FILTERED]') }
    end

    # GET cru (bytes) para imagens.
    def raw_get(path)
      response = HTTParty.get("#{@base}#{path}", headers: { 'X-Api-Key' => @key }, timeout: DEFAULT_TIMEOUT)
      raise Error, "WAHA GET #{path} -> #{response.code}" unless response.success?

      { body: response.body, content_type: response.headers['content-type'] }
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      raise Error, "WAHA GET #{path} falhou: #{e.message}"
    end
  end
end
