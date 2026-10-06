require 'uri'

module Waha
  # Cliente HTTP fino do motor externo (WAHA). Autentica via X-Api-Key. Levanta
  # Waha::Client::Error em qualquer falha, com status + corpo para diagnóstico.
  class Client
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end

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

    def history_source_ids_available?
      version = get('/api/server/version')
      version['chat2youHistorySourceIds'] == 'v1' &&
        version['chat2youHistoryFirstConnectionTimestamp'] == 'v1'
    end

    # ---- CHATS/MENSAGENS ----
    def list_chats(session, limit:, offset:)
      query = URI.encode_www_form(
        limit: limit,
        offset: offset,
        sortBy: 'id',
        sortOrder: 'asc'
      )
      get("/api/#{path_component(session)}/chats?#{query}")
    end

    def list_messages(session, chat_id:, limit:, offset:, before:)
      query = URI.encode_www_form(
        {
          'limit' => limit,
          'offset' => offset,
          'filter.timestamp.lte' => before,
          'sortBy' => 'timestamp',
          'sortOrder' => 'asc',
          'downloadMedia' => false
        }
      )
      get("/api/#{path_component(session)}/chats/#{path_component(chat_id)}/messages?#{query}")
    end

    def get_message(session, chat_id:, message_id:)
      query = URI.encode_www_form(downloadMedia: true)
      path = "/api/#{path_component(session)}/chats/#{path_component(chat_id)}/messages/#{path_component(message_id)}"
      get("#{path}?#{query}")
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

    def get_lid_mapping(session, chat_id:)
      path = chat_id.end_with?('@lid') ? 'lids' : 'lids/pn'
      get("/api/#{path_component(session)}/#{path}/#{path_component(chat_id)}")
    end

    def download_media(url)
      uri = URI.parse(url)
      base = URI.parse(@base)
      unless [uri.scheme, uri.host, uri.port] == [base.scheme, base.host, base.port] &&
             uri.userinfo.nil? && uri.path.start_with?("#{base.path}/api/files/")
        raise Error, 'history_media_origin_mismatch'
      end

      limit = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
      Down.download(url, headers: { 'X-Api-Key' => @key }, max_redirects: 0,
                         max_size: (limit.positive? ? limit : 40).megabytes, open_timeout: 10, read_timeout: 10)
    rescue URI::InvalidURIError
      raise Error, 'history_media_invalid_url'
    rescue Down::TimeoutError, Down::ConnectionError, Down::ServerError => e
      raise Error, "history_media_read_failed #{e.class}", cause: nil
    end

    def get_contact(session, contact_id:)
      query = URI.encode_www_form(session: session, contactId: contact_id)
      get("/api/contacts?#{query}")
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

    def path_component(value)
      URI.encode_www_form_component(value.to_s)
    end

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
      unless response.success?
        raise Error.new("WAHA #{method.upcase} #{path} -> #{response.code}: #{response.body.to_s[0, 300]}", status: response.code)
      end

      response.parsed_response
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
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
