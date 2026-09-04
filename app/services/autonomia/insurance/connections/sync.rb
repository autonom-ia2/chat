# Um único caminho para "falar com o portal e gravar o que voltou": usado por Conectar, Reconectar e
# Atualizar configuração. Contrato: NUNCA levanta erro para fora — falha do connector, formato
# inesperado ou bug viram `status` + `last_error` na conexão, que é o que a tela Conexões exibe.
class Autonomia::Insurance::Connections::Sync
  STATUS_BY_ERROR = {
    auth_required: 'auth_required',
    unavailable: 'offline',
    timeout: 'offline',
    protocol: 'degraded',
    validation: 'degraded'
  }.freeze

  # `last_error` vai para a tela: sem e-mail (login da corretora) e sem token do portal.
  EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
  LONG_TOKEN = /[A-Za-z0-9_\-.]{32,}/

  def initialize(connection, connector: ::Autonomia::Insurance::Connector.client, scan_capabilities: true)
    @connection = connection
    @connector = connector
    @scan_capabilities = scan_capabilities
    @sessions = ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  # Abre (ou reusa) A sessão da conexão e consulta o portal com ELA. Antes, este método fazia dois
  # logins por sincronização — um no status, outro nas capacidades — e cada um invalidava a sessão
  # anterior, inclusive a de uma cotação em andamento.
  def call
    return mark!(status: 'not_configured') unless @connection.credentials_present?

    mark!(status: 'authenticating')
    session = @sessions.resolve!
    apply_status!(@connector.connection_status(provider: @connection.provider, session: session))
    scan!(session) if @scan_capabilities && @connection.ready?
    @connection
  rescue ::Autonomia::Insurance::Connector::Error => e
    # Credencial recusada invalida também o que estava guardado: manter a sessão faria a próxima
    # operação tentar de novo com um portador que o portal já não aceita.
    @connection.forget_session! if e.kind == :auth_required
    mark!(status: STATUS_BY_ERROR.fetch(e.kind, 'degraded'), error: "#{e.kind}: #{e.message}")
  rescue StandardError => e
    # Formato inesperado, validação do model ou bug: registra a CLASSE, nunca a mensagem (que pode
    # carregar payload do portal), e deixa a conexão num estado consultável em vez de estourar 500.
    mark!(status: 'degraded', error: "unexpected: #{e.class.name}")
  end

  private

  def apply_status!(payload)
    raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'status payload is not a hash') unless payload.is_a?(Hash)

    status = payload['status'].to_s
    unless ::Autonomia::Insurance::Connection::STATUSES.include?(status)
      raise ::Autonomia::Insurance::Connector::Error.new(:protocol, "unknown status #{status.truncate(30)}")
    end

    @connection.update!(
      status: status,
      external_account_label: payload['account_label'].to_s.truncate(120).presence,
      session_expires_at: payload['session_expires_at'],
      last_authenticated_at: Time.current,
      last_healthcheck_at: Time.current,
      last_error: nil
    )
  end

  def scan!(session)
    mark!(status: 'discovering')
    map = @connector.capabilities(provider: @connection.provider, session: session)
    raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'capabilities payload is not a hash') unless map.is_a?(Hash)

    @connection.update!(
      status: 'ready',
      capabilities: map,
      capabilities_version: map['scanned_at'],
      last_capability_scan_at: Time.current
    )
  end

  def mark!(status:, error: nil)
    @connection.update!(status: status, last_error: sanitize(error), last_healthcheck_at: Time.current)
    @connection
  end

  def sanitize(message)
    return nil if message.blank?

    message.to_s.gsub(EMAIL, '<email>').gsub(LONG_TOKEN, '<redacted>').truncate(160)
  end
end
