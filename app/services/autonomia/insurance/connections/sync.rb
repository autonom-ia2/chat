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

  # A causa que o adapter classifica quando o portal recusa uma SESSAO GUARDADA (e nao a credencial).
  # Ela nao e falha do corretor e nao pede nada dele: pede que a gente abra outra sessao.
  SESSAO_PERDIDA = 'session_lost'.freeze

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
    # `with_fresh_session` e não `resolve!`: a sessão guardada pode ter sido derrubada por um login
    # feito no portal pelo navegador, e só descobrimos isso quando o portal recusa. Sem a renovação,
    # a conexão fica "credencial recusada" com a credencial válida até o prazo vencer.
    @sessions.with_fresh_session do |session|
      apply_status!(consultar_status(session))
      scan!(@connection.session || session) if @scan_capabilities && @connection.ready?
    end
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

  # Uma consulta de status, e UMA renovacao quando o portal recusa a sessao que guardavamos.
  #
  # Sessao perdida chega como PAYLOAD de sucesso, nao como excecao: o adapter responde 200 dizendo
  # "nao deu, e o motivo e este". Por isso o `with_fresh_session`, que so reage a excecao, nunca via
  # este caso -- e ele e o caso mais comum. Em 05/09/2026 a tela ficou dizendo "credencial recusada"
  # com a credencial certa exatamente por aqui: a renovacao existia e este caminho nao a chamava.
  #
  # UMA tentativa. Se a sessao nova tambem for recusada, o problema nao e a sessao, e insistir so
  # multiplica login no portal.
  def consultar_status(session)
    payload = @connector.connection_status(provider: @connection.provider, session: session)
    return payload unless sessao_perdida?(payload)

    @connector.connection_status(provider: @connection.provider, session: @sessions.renew!)
  end

  def sessao_perdida?(payload)
    payload.is_a?(Hash) && payload.dig('failure', 'cause') == SESSAO_PERDIDA
  end

  def apply_status!(payload)
    raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'status payload is not a hash') unless payload.is_a?(Hash)

    status = payload['status'].to_s
    unless ::Autonomia::Insurance::Connection::STATUSES.include?(status)
      raise ::Autonomia::Insurance::Connector::Error.new(:protocol, "unknown status #{status.truncate(30)}")
    end

    # `last_error` só é limpo quando a conexão está REALMENTE boa. Antes ele era zerado sempre que o
    # payload fosse um Hash válido — e um Hash válido dizendo `degraded` é exatamente o caso em que
    # o motivo importa. Em 04/09/2026 uma conexão real caiu aqui: status `degraded`, `last_error`
    # nulo, e a tela mostrando "conectado com alertas" sem dizer qual alerta.
    #
    # `reason` vem do adapter e já chega redatado. O fallback existe para adapter antigo, que não
    # manda o campo: melhor "status degraded" do que nada.
    ok = status == 'ready'
    @connection.update!(
      status: status,
      external_account_label: payload['account_label'].to_s.truncate(120).presence,
      session_expires_at: payload['session_expires_at'],
      last_authenticated_at: Time.current,
      last_healthcheck_at: Time.current,
      last_error: ok ? nil : sanitize(payload['reason'].presence || "status #{status}"),
      metadata: @connection.metadata.to_h.merge(diagnostico(payload, ok))
    )
  end

  # O diagnostico estruturado que a tela usa (criterios 1.1, 1.2 e 1.6). Vai em `metadata` porque e
  # jsonb e ja existe: criar coluna para cada campo novo de diagnostico transformaria toda melhoria
  # de mensagem numa migration em producao.
  #
  # `failure` responde de QUEM e a acao -- e so isso autoriza a tela a pedir a senha de volta.
  # `evidence` responde o que foi verificado e quando, para a tela parar de dizer "ha 3 minutos".
  # `layers` responde o que NAO foi verificado, que e a metade que o 1.2 protege.
  def diagnostico(payload, saudavel)
    {
      'last_failure' => saudavel ? nil : payload['failure'],
      'last_evidence' => payload['evidence'],
      'layers' => payload['layers']
    }
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
