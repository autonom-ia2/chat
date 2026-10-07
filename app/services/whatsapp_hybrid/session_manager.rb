# Ciclo de vida da sessão WAHA auxiliar de uma caixa Cloud (chat#1067).
# A sessão nasce SEM App Chatwoot: se tivesse, criaria uma segunda caixa com todo o inbound do número.
# O único webhook é o nosso, assinado (HMAC), e só com estado da sessão e confirmação de entrega:
# nenhuma mensagem recebida passa por ele. A Cloud continua recebendo tudo; a sessão só envia.
class WhatsappHybrid::SessionManager
  STATUS_MAP = {
    'WORKING' => 'connected',
    'SCAN_QR_CODE' => 'awaiting_scan',
    'STARTING' => 'connecting',
    'FAILED' => 'failed',
    'STOPPED' => 'disconnected'
  }.freeze

  SESSION_IGNORE = { status: true, broadcast: true, channels: true, groups: true }.freeze
  WEBHOOK_EVENTS = %w[session.status message.ack].freeze

  def initialize(connection, client: Waha::Client.new)
    @connection = connection
    @client = client
  end

  def self.connect!(inbox:, client: Waha::Client.new)
    connection = WhatsappHybrid::Connection.find_or_create_by!(inbox: inbox) do |record|
      record.account = inbox.account
      record.session_name = WhatsappHybrid::Config.session_name_for(inbox)
    end
    new(connection, client: client).tap(&:ensure_session!)
  end

  attr_reader :connection

  def ensure_session!
    remote = fetch_remote
    if remote.blank?
      @client.create_session(connection.session_name, start: true, config: session_config)
    elsif remote['status'] == 'STOPPED'
      @client.start_session(connection.session_name)
    end
    refresh!
  end

  # Consulta o motor e grava estado + número conectado. Retorna o estado público.
  def refresh!
    remote = fetch_remote
    ensure_webhook!(remote)
    status = STATUS_MAP.fetch(remote['status'].to_s, remote.blank? ? 'disconnected' : 'connecting')
    phone = remote.dig('me', 'id').to_s.split('@').first.to_s.delete('^0-9').presence
    apply_status!(status, phone: phone)
    refresh_capping! if status == 'connected'
    status
  end

  # O limite muda devagar; a aba e a revalidação antes do envio mantêm o retrato em dia.
  def refresh_capping!
    WhatsappHybrid::Capping.new(connection).apply!(@client.capping(connection.session_name))
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] capping refresh failed inbox=#{connection.inbox_id}: #{e.class}")
  end

  # Grava o estado vindo do motor (consulta ou webhook) e avisa os administradores uma vez por queda.
  def apply_status!(status, phone: nil)
    was_connected = connection.status == 'connected'
    connection.update!(status: status, connected_phone: phone || connection.connected_phone, status_checked_at: Time.current)
    if status == 'connected'
      connection.update!(down_alerted_at: nil) if connection.down_alerted_at
    elsif was_connected && connection.routable_when_connected? && connection.down_alerted_at.nil?
      connection.update!(down_alerted_at: Time.current)
      WhatsappHybrid::DownAlert.new(connection).deliver!
    end
  end

  def qr
    return if connection.status == 'connected'

    @client.qr_value(connection.session_name)['value']
  rescue Waha::Client::Error
    nil
  end

  def pairing_code
    @client.request_pairing_code(connection.session_name, phone: connection.cloud_phone_digits)['code']
  end

  def reconnect!
    # Sessão apagada no motor (reinício, limpeza): recria em vez de falhar.
    return ensure_session! if fetch_remote.blank?

    begin
      @client.logout_session(connection.session_name)
    rescue Waha::Client::Error
      @client.restart_session(connection.session_name)
    end
    @client.start_session(connection.session_name) if fetch_remote['status'] == 'STOPPED'
    connection.update!(status: 'connecting', connected_phone: nil)
  end

  # Apagar a conexão dispara o logout e a exclusão da sessão no motor (TeardownSessionJob).
  def disconnect!
    connection.destroy!
  end

  private

  def session_config
    {
      ignore: SESSION_IGNORE,
      webhooks: [{ url: connection.webhook_url, events: WEBHOOK_EVENTS, hmac: { key: connection.ensure_webhook_secret! } }]
    }
  end

  # Sessão criada antes do webhook (piloto) ou com outro endereço: grava a configuração uma vez.
  def ensure_webhook!(remote)
    return if remote.blank?

    urls = Array(remote.dig('config', 'webhooks')).pluck('url')
    return if urls.include?(connection.webhook_url)

    @client.update_session(connection.session_name, config: session_config, apps: nil)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] webhook setup failed inbox=#{connection.inbox_id}: #{e.class}")
  end

  def fetch_remote
    @client.get_session(connection.session_name) || {}
  rescue Waha::Client::Error
    {}
  end
end
