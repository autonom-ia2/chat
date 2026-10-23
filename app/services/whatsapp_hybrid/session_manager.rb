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
  # Gravar a configuração reinicia a sessão no motor: a atualização só agenda a troca do proxy uma vez por hora (#1516).
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

  # Pausada (#1487): nunca cria nem religa a sessão; só o "Retomar" faz isso.
  def ensure_session!
    return refresh! if connection.paused?

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
  # Pausada: só lê. Gravar a configuração reinicia a sessão no motor e desfaria a pausa.
  def refresh!(sync_proxy: true)
    remote = fetch_remote
    sync_remote_config!(remote, proxy_mode: sync_proxy ? :refresh : :skip) unless connection.paused?
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

  # Grava o estado vindo do motor (consulta ou webhook). A queda só vira aviso aos administradores se durar a carência
  # (WhatsappHybrid::DownAlert::CARENCIA, #2112): o WhatsApp fecha o websocket e o motor reconecta em segundos.
  def apply_status!(status, phone: nil)
    was_connected = connection.status == 'connected'
    WhatsappProxy::Health.record_drop!(connection.session_name) if proxy_drop?(was_connected, status)
    paired = status == 'connected' && fresh_pairing?
    connection.update!(status: status, connected_phone: phone || connection.connected_phone, status_checked_at: Time.current)
    WhatsappHybrid::ReachOut.paired!(connection) if paired
    status == 'connected' ? clear_down_alert! : schedule_down_alert!(was_connected)
  end

  # A sessão como o motor a vê ({} quando não existe ou o motor não respondeu).
  def fetch_remote
    @client.get_session(connection.session_name) || {}
  rescue Waha::Client::Error
    {}
  end

  def qr
    return if connection.status == 'connected' || connection.paused?

    @client.qr_value(connection.session_name)['value']
  rescue Waha::Client::Error
    nil
  end

  def pairing_code
    @client.request_pairing_code(connection.session_name, phone: connection.cloud_phone_digits)['code']
  end

  def reconnect!
    # Pedir novo QR é decisão de religar: desfaz a pausa, com a sessão no ar antes do logout (WakeSession).
    WhatsappHybrid::WakeSession.unpause!(@client, connection)
    # Sessão apagada no motor (reinício, limpeza): recria em vez de falhar.
    return ensure_session! if fetch_remote.blank?

    begin
      @client.logout_session(connection.session_name)
    rescue Waha::Client::Error
      @client.restart_session(connection.session_name)
    end
    sync_on_reconnect
    @client.start_session(connection.session_name) if fetch_remote['status'] == 'STOPPED'
    connection.update!(status: 'connecting', connected_phone: nil)
  end

  # Apagar a conexão dispara o logout e a exclusão da sessão no motor (TeardownSessionJob).
  def disconnect!
    connection.destroy!
  end

  private

  # Reconectar já reinicia a sessão: hora de conferir na lista se o IP atribuído continua valendo. Só sessão com
  # atribuição pega a trava do ApplyJob; ocupada (outra troca em andamento) ou Redis fora: grava só o webhook que
  # faltava, sem mexer no proxy — a reconciliação converge com o motor depois.
  def sync_on_reconnect
    return sync_remote_config!(fetch_remote, proxy_mode: :skip) if managed_assignment.nil?

    verified = WhatsappProxy::SessionLock.with(connection.session_name) { sync_remote_config!(fetch_remote, proxy_mode: :verify) }
    return unless verified == :locked

    Rails.logger.info("[whatsapp_hybrid] reconnect inbox=#{connection.inbox_id}: troca de proxy em andamento")
    sync_remote_config!(fetch_remote, proxy_mode: :skip)
  rescue Redis::BaseError
    sync_remote_config!(fetch_remote, proxy_mode: :skip)
  end

  # Sinal rápido de IP ruim (#1516): conectado → conectando/falhou. Aparelho desvinculado (QR) e pausa (#1487) não contam.
  def proxy_drop?(was_connected, status) = was_connected && !connection.paused? && %w[connecting failed].include?(status)

  def clear_down_alert!
    WhatsappHybrid::DownAlert.new(connection).voltou!
    connection.update!(down_alerted_at: nil) if connection.down_alerted_at
  end

  def schedule_down_alert!(was_connected)
    return unless was_connected && connection.routable_when_connected? && connection.down_alerted_at.nil?

    WhatsappHybrid::DownAlert.new(connection).agendar!
  end

  # Pareamento novo (chat#1486): saiu da leitura do QR, ou ainda não havia aparelho (primeira vez ou depois de
  # `reconnect!`, que apaga o número). Reconexão automática do websocket e nova consulta com a sessão já conectada
  # não são pareamento.
  def fresh_pairing?
    return false if connection.status == 'connected'

    connection.status == 'awaiting_scan' || connection.connected_phone.blank?
  end

  # Sessão nova já nasce com o proxy. Se o motor recusar, o número deixa o IP (#1516).
  def create_remote_session!
    proxy = @proxy_assigner.for(connection.session_name)
    @client.create_session(connection.session_name, start: true, config: session_config(proxy&.to_session_config))
    proxy ? @proxy_assigner.mark_applied!(connection.session_name, proxy) : @proxy_assigner.mark_pending!(connection.session_name)
  rescue Waha::Client::Error
    @proxy_assigner.release!(connection.session_name) if proxy
    raise
  end

  # proxy: bloco `config.proxy` do motor (com credencial) — vai só no corpo do pedido, nunca em log.
  def session_config(proxy = nil)
    {
      ignore: SESSION_IGNORE,
      webhooks: [{ url: connection.webhook_url, events: WEBHOOK_EVENTS, hmac: { key: connection.ensure_webhook_secret! } }],
      proxy: proxy
    }.compact
  end

  # Grava a configuração quando falta o webhook (sessão do piloto, endereço novo) e, ao reconectar, o proxy atribuído.
  # Sempre mescla sobre a configuração do motor: o proxy que a sessão já tem fica (o motor só guarda as chaves que
  # conhece).
  # proxy_mode: :refresh (atualização: só agenda a troca do proxy, nunca PUT na requisição), :verify (reconectar:
  # confere o IP e grava junto, a sessão já está reiniciando) ou :skip (envio de mensagem).
  def sync_remote_config!(remote, proxy_mode:)
    return if remote.blank?

    remote_proxy = remote.dig('config', 'proxy').presence
    schedule_proxy!(remote, remote_proxy) if proxy_mode == :refresh
    proxy = proxy_mode == :verify ? verified_proxy(remote_proxy) : nil
    return if proxy.nil? && webhook_configured?(remote)

    write_config!(remote, proxy)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] session config update failed inbox=#{connection.inbox_id}: #{e.class}")
  end

  def write_config!(remote, proxy)
    config = remote['config'].to_h.merge(session_config(proxy&.to_session_config).deep_stringify_keys)
    @client.update_session(connection.session_name, config: config)
    @proxy_assigner.mark_applied!(connection.session_name, proxy) if proxy
  end

  def webhook_configured?(remote)
    Array(remote.dig('config', 'webhooks')).pluck('url').include?(connection.webhook_url)
  end

  # Proxy a gravar ao reconectar, ou nil para manter o que a sessão tem. Só sessão que já tem atribuição: a existente sem
  # atribuição só entra pela importação ou pela rake `autonomia:whatsapp_proxy:migrar` (uma por vez).
  def verified_proxy(remote_proxy)
    assignment = managed_assignment
    return if assignment.nil? || assignment.in_backoff?

    proxy = @proxy_assigner.for(connection.session_name)
    proxy unless proxy.nil? || WhatsappProxy::Server.same?(remote_proxy&.dig('server'), proxy.server)
  end

  # Sessão conectada com atribuição que o motor ainda não tem: agenda a troca (WhatsappProxy::ApplyJob), no máximo uma
  # vez por hora e nunca durante o recuo de uma troca desfeita. Abrir a aba nunca migra sessão sem atribuição.
  def schedule_proxy!(remote, remote_proxy)
    return unless remote['status'] == 'WORKING'

    assignment = managed_assignment
    return unless assignment && proxy_change_due?(assignment, remote_proxy)

    return if proxy_rewrite_cooling_down?

    assignment.scheduled!
    WhatsappProxy::ApplyJob.perform_later(connection.session_name)
  end

  def proxy_change_due?(assignment, remote_proxy)
    return false if assignment.external? || assignment.in_backoff?

    !(remote_proxy && WhatsappProxy::Server.same?(remote_proxy['server'], assignment.server))
  end

  # A atribuição da sessão (uma consulta), só com o recurso ligado; nil = sessão sem proxy gerenciado.
  def managed_assignment
    return unless @proxy_assigner.enabled?

    WhatsappProxy::Assignment.find_by(session_name: connection.session_name)
  end

  # Redis fora: considera em pausa (falha fechada), para nunca agendar trocas em sequência.
  def proxy_rewrite_cooling_down?
    !::Redis::Alfred.set("whatsapp_proxy:rewrite:#{connection.session_name}", '1', nx: true, ex: PROXY_REWRITE_COOLDOWN)
  rescue Redis::BaseError
    true
  end
end
