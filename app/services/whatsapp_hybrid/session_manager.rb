# Ciclo de vida da sessão WAHA auxiliar de uma caixa Cloud (chat#1067).
# A sessão nasce SEM App Chatwoot e SEM webhook: se tivesse, criaria uma segunda caixa com todo o
# inbound do número. A Cloud continua recebendo tudo; a sessão só envia.
class WhatsappHybrid::SessionManager
  STATUS_MAP = {
    'WORKING' => 'connected',
    'SCAN_QR_CODE' => 'awaiting_scan',
    'STARTING' => 'connecting',
    'FAILED' => 'failed',
    'STOPPED' => 'disconnected'
  }.freeze

  SESSION_IGNORE = { status: true, broadcast: true, channels: true, groups: true }.freeze

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
      @client.create_session(connection.session_name, start: true, config: { ignore: SESSION_IGNORE })
    elsif remote['status'] == 'STOPPED'
      @client.start_session(connection.session_name)
    end
    refresh!
  end

  # Consulta o motor e grava estado + número conectado. Retorna o estado público.
  def refresh!
    remote = fetch_remote
    status = STATUS_MAP.fetch(remote['status'].to_s, remote.blank? ? 'disconnected' : 'connecting')
    phone = remote.dig('me', 'id').to_s.split('@').first.to_s.delete('^0-9').presence
    connection.update!(status: status, connected_phone: phone || connection.connected_phone, status_checked_at: Time.current)
    status
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

  def disconnect!
    begin
      @client.logout_session(connection.session_name)
    rescue Waha::Client::Error => e
      Rails.logger.warn("[whatsapp_hybrid] logout failed inbox=#{connection.inbox_id}: #{e.class}")
    end
    @client.delete_session(connection.session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] delete failed inbox=#{connection.inbox_id}: #{e.class}")
  ensure
    connection.destroy!
  end

  private

  def fetch_remote
    @client.get_session(connection.session_name) || {}
  rescue Waha::Client::Error
    {}
  end
end
