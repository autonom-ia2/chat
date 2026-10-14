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
  # Gravar a configuração reinicia a sessão no motor: a atualização só põe/corrige o proxy uma vez por hora (#1516).
  PROXY_REWRITE_COOLDOWN = 1.hour.to_i

  def initialize(connection, client: Waha::Client.new, proxy_assigner: WhatsappProxy::Assigner.new)
    @connection = connection
    @client = client
    @proxy_assigner = proxy_assigner
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
      create_remote_session!
    elsif remote['status'] == 'STOPPED'
      @client.start_session(connection.session_name)
    end
    refresh!
  end

  # Consulta o motor e grava estado + número conectado. Retorna o estado público.
  # sync_proxy: false no envio de mensagem — pôr o proxy reinicia a sessão e derrubaria o próprio envio.
  def refresh!(sync_proxy: true)
    remote = fetch_remote
    sync_remote_config!(remote, proxy_mode: sync_proxy ? :refresh : :skip)
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

  # O WhatsApp pode limitar conversas novas por algumas horas; a aba mostra até quando (chat#1480).
  # Só a aba chama: fica fora do envio e dos webhooks. Falha do motor marca a tentativa, para a aba
  # não repetir a consulta a cada atualização, e mantém o último retrato.
  def refresh_timelock!
    timelock = WhatsappHybrid::Timelock.new(connection)
    return if connection.status != 'connected' || timelock.fresh?

    timelock.apply!(@client.timelock(connection.session_name))
  rescue Waha::Client::Error => e
    timelock.checked!
    Rails.logger.warn("[whatsapp_hybrid] timelock refresh failed inbox=#{connection.inbox_id}: #{e.class}")
  end

  # Grava o estado vindo do motor (consulta ou webhook) e avisa os administradores uma vez por queda.
  def apply_status!(status, phone: nil)
    was_connected = connection.status == 'connected'
    paired = status == 'connected' && fresh_pairing?
    connection.update!(status: status, connected_phone: phone || connection.connected_phone, status_checked_at: Time.current)
    WhatsappHybrid::ReachOut.paired!(connection) if paired
    status == 'connected' ? clear_down_alert! : alert_down!(was_connected)
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
    # Reconectar já reinicia a sessão: hora de conferir na lista se o IP atribuído continua valendo.
    sync_remote_config!(fetch_remote, proxy_mode: :verify)
    @client.start_session(connection.session_name) if fetch_remote['status'] == 'STOPPED'
    connection.update!(status: 'connecting', connected_phone: nil)
  end

  # Troca agendada pela reconciliação (WhatsappProxy::ApplyJob). Reinicia a sessão no motor.
  def apply_proxy!(proxy)
    @client.update_session(connection.session_name, config: session_config(proxy.to_session_config), apps: nil)
  end

  # Apagar a conexão dispara o logout e a exclusão da sessão no motor (TeardownSessionJob).
  def disconnect!
    connection.destroy!
  end

  private

  def clear_down_alert!
    connection.update!(down_alerted_at: nil) if connection.down_alerted_at
  end

  def alert_down!(was_connected)
    return unless was_connected && connection.routable_when_connected? && connection.down_alerted_at.nil?

    connection.update!(down_alerted_at: Time.current)
    WhatsappHybrid::DownAlert.new(connection).deliver!
  end

  # Pareamento novo (chat#1486): saiu da leitura do QR, ou ainda não havia aparelho (primeira vez ou depois de
  # `reconnect!`, que apaga o número). Reconexão automática do websocket e nova consulta com a sessão já conectada
  # não são pareamento.
  def fresh_pairing?
    return false if connection.status == 'connected'

    connection.status == 'awaiting_scan' || connection.connected_phone.blank?
  end

  def create_remote_session!
    proxy = @proxy_assigner.for(connection.session_name)
    @client.create_session(connection.session_name, start: true, config: session_config(proxy&.to_session_config))
    @proxy_assigner.mark_applied!(connection.session_name, proxy) if proxy
  end

  # proxy: bloco `config.proxy` do motor (com credencial) — vai só no corpo do pedido, nunca em log.
  def session_config(proxy = nil)
    {
      ignore: SESSION_IGNORE,
      webhooks: [{ url: connection.webhook_url, events: WEBHOOK_EVENTS, hmac: { key: connection.ensure_webhook_secret! } }],
      proxy: proxy
    }.compact
  end

  # Grava a configuração quando falta o webhook (sessão do piloto, endereço novo) ou o proxy atribuído (#1516).
  # Nunca apaga o proxy que a sessão já tem: sem proxy novo, regrava o que veio do motor.
  # proxy_mode: :refresh (atualização), :verify (reconectar: confere o IP na lista) ou :skip (envio de mensagem).
  def sync_remote_config!(remote, proxy_mode:)
    return if remote.blank?

    remote_proxy = remote.dig('config', 'proxy').presence
    proxy = proxy_for(remote_proxy, proxy_mode)
    return if proxy.nil? && webhook_configured?(remote)

    write_config!(proxy, remote_proxy)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] session config update failed inbox=#{connection.inbox_id}: #{e.class}")
  end

  def write_config!(proxy, remote_proxy)
    @client.update_session(connection.session_name, config: session_config(proxy&.to_session_config || remote_proxy), apps: nil)
    @proxy_assigner.mark_applied!(connection.session_name, proxy) if proxy
  end

  def webhook_configured?(remote)
    Array(remote.dig('config', 'webhooks')).pluck('url').include?(connection.webhook_url)
  end

  # Proxy a gravar, ou nil para manter o que a sessão tem. Proxy posto à mão sem registro nunca é trocado.
  def proxy_for(remote_proxy, proxy_mode)
    return if proxy_mode == :skip || !@proxy_assigner.enabled?
    return unless proxy_change_wanted?(remote_proxy, proxy_mode)

    proxy = @proxy_assigner.for(connection.session_name, honor_backoff: proxy_mode == :refresh)
    proxy unless proxy.nil? || proxy.server == remote_proxy&.dig('server')
  end

  def proxy_change_wanted?(remote_proxy, proxy_mode)
    assignment = WhatsappProxy::Assignment.find_by(session_name: connection.session_name)
    return false if remote_proxy && assignment.nil?

    proxy_mode == :verify || !proxy_settled?(remote_proxy, assignment)
  end

  # Na atualização só consulta a Webshare quando falta proxy ou ele difere do atribuído, e no máximo uma regravação por hora.
  def proxy_settled?(remote_proxy, assignment)
    (remote_proxy && remote_proxy['server'] == assignment.server) || proxy_rewrite_cooling_down?
  end

  def proxy_rewrite_cooling_down?
    key = "whatsapp_proxy:rewrite:#{connection.session_name}"
    return true if ::Redis::Alfred.get(key).present?

    ::Redis::Alfred.setex(key, '1', PROXY_REWRITE_COOLDOWN)
    false
  rescue Redis::BaseError
    false
  end

  def fetch_remote
    @client.get_session(connection.session_name) || {}
  rescue Waha::Client::Error
    {}
  end
end
