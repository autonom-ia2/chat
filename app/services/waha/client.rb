require 'uri'

module Waha
  # Cliente HTTP fino do motor externo (WAHA). Autentica via X-Api-Key. Levanta
  # Waha::Client::Error em qualquer falha, com status + corpo para diagnóstico.
  class Client
    class Error < StandardError; end
    # A resposta não chegou: não dá para saber se o motor executou o pedido.
    class Timeout < Error; end

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

    def get_session(name)
      get("/api/sessions/#{name}")
    end

    def update_session(name, config:, apps:)
      put("/api/sessions/#{name}", { config: config, apps: apps })
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

    # "digitando…" antes do envio (WhatsApp Híbrido, chat#1067).
    def start_typing(session:, chat_id:)
      post('/api/startTyping', { session: session, chatId: chat_id })
    end

    def stop_typing(session:, chat_id:)
      post('/api/stopTyping', { session: session, chatId: chat_id })
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

    def check_contact_exists(phone:, session:)
      query = URI.encode_www_form(phone: phone, session: session)
      get("/api/contacts/check-exists?#{query}")
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

    def post(path, body = nil)
      request(:post, path, body)
    end

    def get(path)
      request(:get, path)
    end

    def put(path, body)
      request(:put, path, body)
    end

    def delete(path)
      request(:delete, path)
    end

    def request(method, path, body = nil)
      response = HTTParty.public_send(
        method, "#{@base}#{path}",
        headers: headers, body: body.nil? ? nil : body.to_json, timeout: DEFAULT_TIMEOUT
      )
      raise Error, "WAHA #{method.upcase} #{path} -> #{response.code}: #{response.body.to_s[0, 300]}" unless response.success?

      response.parsed_response
    rescue Net::ReadTimeout => e
      raise Timeout, "WAHA #{method.upcase} #{path} sem resposta: #{e.message}"
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Errno::ECONNREFUSED => e
      raise Error, "WAHA #{method.upcase} #{path} falhou: #{e.message}"
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
