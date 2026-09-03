# Um único caminho para "falar com o portal e gravar o que voltou": usado por Conectar,
# Reconectar e Atualizar configuração. Nunca levanta erro do connector para fora — traduz em
# status + last_error na própria conexão, que é o que a tela Conexões exibe.
class Autonomia::Insurance::Connections::Sync
  STATUS_BY_ERROR = {
    auth_required: 'auth_required',
    unavailable: 'offline',
    timeout: 'offline',
    protocol: 'degraded',
    validation: 'degraded'
  }.freeze

  def initialize(connection, connector: ::Autonomia::Insurance::Connector.client, scan_capabilities: true)
    @connection = connection
    @connector = connector
    @scan_capabilities = scan_capabilities
  end

  def call
    unless @connection.credentials_present?
      @connection.update!(status: 'not_configured', last_error: nil)
      return @connection
    end

    @connection.update!(status: 'authenticating', last_error: nil)
    status = @connector.connection_status(**credentials)
    @connection.assign_attributes(
      status: status['status'],
      external_account_label: status['account_label'],
      session_expires_at: status['session_expires_at'],
      last_authenticated_at: Time.current,
      last_healthcheck_at: Time.current,
      last_error: nil
    )
    @connection.save!

    scan! if @scan_capabilities && @connection.ready?
    @connection
  rescue ::Autonomia::Insurance::Connector::Error => e
    @connection.update!(
      status: STATUS_BY_ERROR.fetch(e.kind, 'degraded'),
      last_error: "#{e.kind}: #{e.message}".truncate(200),
      last_healthcheck_at: Time.current
    )
    @connection
  end

  private

  def scan!
    @connection.update!(status: 'discovering')
    map = @connector.capabilities(**credentials)
    @connection.update!(
      status: 'ready',
      capabilities: map,
      capabilities_version: map['scanned_at'],
      last_capability_scan_at: Time.current
    )
  end

  def credentials
    { provider: @connection.provider, username: @connection.username, password: @connection.password }
  end
end
