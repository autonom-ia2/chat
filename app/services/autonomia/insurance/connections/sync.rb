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

  # O formulário que a varredura busca sempre, com o ramo ativo ou não (`produtos_do_mapa`).
  AUTO = 'auto'.freeze

  # `last_error` vai para a tela: sem e-mail (login da corretora) e sem token do portal.
  EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
  LONG_TOKEN = /[A-Za-z0-9_\-.]{32,}/

  # `espera_do_login:` é quanto este chamador aguarda o login de outro processo (ver `Session`). A tela
  # (requisição web, Rack::Timeout de 15 s) passa menos que o padrão dos jobs.
  def initialize(connection, connector: ::Autonomia::Insurance::Connector.client, scan_capabilities: true,
                 espera_do_login: ::Autonomia::Insurance::Connections::Session::TRAVA_DO_LOGIN)
    @connection = connection
    @connector = connector
    @renovou = false
    @scan_capabilities = scan_capabilities
    @sessions = ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector, espera: espera_do_login)
  end

  # Abre (ou reusa) A sessão da conexão e consulta o portal com ELA. Antes, este método fazia dois
  # logins por sincronização — um no status, outro nas capacidades —, e cada um é uma chamada de até
  # `Http::READ_TIMEOUT` segundos ao portal para receber de volta a sessão que já tínhamos.
  #
  # (Correção de 11/09/2026: a frase aqui era "e cada um invalidava a sessão anterior, inclusive a
  # de uma cotação em andamento". Medido e falso — logins da mesma conta compartilham a sessão. O
  # que se economiza é login, não sobrevivência de cotação. Ver `connections/session.rb`.)
  def call
    anterior = @connection.status
    sincronizar
  ensure
    registrar_mudanca(anterior)
  end

  private

  def sincronizar
    return mark!(status: 'not_configured') unless @connection.credentials_present?

    marcar_inicio!
    # `with_fresh_session` e não `resolve!`: `session_live?` só conhece o PRAZO QUE NÓS GRAVAMOS, e
    # prazo gravado não é prova — a sessão pode ter acabado antes dele, e só descobrimos isso quando
    # o portal recusa. Sem a renovação, a conexão fica "credencial recusada" com a credencial válida
    # até o prazo vencer.
    #
    # (Correção de 11/09/2026: o motivo escrito aqui era "pode ter sido derrubada por um login feito
    # no portal pelo navegador". Medido e falso: logins da mesma conta não derrubam nada.)
    @sessions.with_fresh_session do |session|
      apply_status!(consultar_status(session))
      scan!(@connection.session || session) if @scan_capabilities && @connection.ready?
    end
    @connection
  rescue ::Autonomia::Insurance::Connector::Error => e
    # Credencial recusada invalida também o que estava guardado: manter a sessão faria a próxima
    # operação tentar de novo com um portador que o portal já não aceita.
    @connection.forget_session! if e.kind == :auth_required
    mark!(status: STATUS_BY_ERROR.fetch(e.kind, 'degraded'), error: "#{e.kind}: #{e.message}",
          failure: diagnostico_do_erro(e))
  rescue StandardError => e
    # Formato inesperado, validação do model ou bug: registra a CLASSE, nunca a mensagem (que pode
    # carregar payload do portal), e deixa a conexão num estado consultável em vez de estourar 500.
    mark!(status: 'degraded', error: "unexpected: #{e.class.name}", failure: nil)
  end

  # Conexão que já serve às ferramentas NÃO passa por `authenticating`: ela continua valendo até o
  # portal responder, e é a resposta que decide o novo estado. Antes, toda checagem de 30 minutos
  # escondia a conexão da Lia por 1 a 60 s, 48 vezes por dia (auditoria da conexão, 05/11/2026,
  # achado 3). O transitório fica para quem ainda não está pronta, onde ele é o que a tela mostra.
  def marcar_inicio!
    mark!(status: 'authenticating') unless @connection.usable?
  end

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
    # Só renova sessão REUSADA, como o `with_fresh_session`: uma que acabou de nascer e já voltou
    # recusada não melhora com outro login (o portal devolveria a mesma).
    return payload unless sessao_perdida?(payload) && !@renovou && @sessions.sessao_reusada?

    # UMA renovação por sincronização, contada aqui e não no fluxo. `with_fresh_session` também
    # renova, mas só quando o adapter LEVANTA — se as duas renovações puderem correr no mesmo
    # `call`, o portal leva três logins onde a regra diz um.
    @renovou = true
    @connector.connection_status(provider: @connection.provider, session: @sessions.renew!(session))
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
    # UMA escrita, dentro do lock. Separar status e diagnóstico em duas transações abre uma janela
    # em que a tela lê `ready` com o `failure` anterior ainda gravado — e é o `failure`, não o
    # status, que decide se ela pede a senha de volta. Seria a mesma classe de defeito do incidente:
    # badge de conectado ao lado de "confira sua senha".
    #
    # O lock também é o que protege da corrida com o polling de cotação, que escreve no mesmo jsonb.
    @connection.with_lock do
      @connection.update!(
        status: status,
        external_account_label: payload['account_label'].to_s.truncate(120).presence,
        session_expires_at: prazo_da_sessao(payload),
        last_authenticated_at: Time.current,
        last_healthcheck_at: Time.current,
        last_error: ok ? nil : sanitize(payload['reason'].presence || "status #{status}"),
        metadata: @connection.metadata.to_h.merge(diagnostico(payload, ok))
      )
    end
  end

  # Resposta sem prazo NÃO apaga o prazo gravado (auditoria da conexão, 05/11/2026, achado 9). O adapter
  # só manda `session_expires_at` quando abriu ou leu uma sessão; numa resposta de falha o campo não vem,
  # e gravar nil fazia placa, CEP, atividade e proposta perderem a sessão viva até o próximo login. Quem
  # invalida a sessão de verdade é o `forget_session!`, na recusa.
  def prazo_da_sessao(payload)
    payload['session_expires_at'].presence || @connection.session_expires_at
  end

  # O diagnostico estruturado que a tela usa (criterios 1.1, 1.2 e 1.6). Vai em `metadata` porque e
  # jsonb e ja existe: criar coluna para cada campo novo de diagnostico transformaria toda melhoria
  # de mensagem numa migration em producao.
  #
  # `failure` responde de QUEM e a acao -- e so isso autoriza a tela a pedir a senha de volta.
  # `evidence` responde o que foi verificado e quando, para a tela parar de dizer "ha 3 minutos".
  # `layers` responde o que NAO foi verificado, que e a metade que o 1.2 protege.
  def diagnostico(payload, saudavel)
    # Sanitizado como o `last_error`, e pelo mesmo motivo: vem da mesma resposta do adapter e vai
    # para a mesma tela. Aplicar a régua só no campo de texto e deixar os estruturados crus é
    # confiar que o adapter nunca vai ficar mais verboso — e `detail` e `reason` são exatamente os
    # campos que crescem quando alguém precisa depurar.
    {
      'last_failure' => saudavel ? nil : sanitize_deep(payload['failure']),
      'last_evidence' => sanitize_deep(payload['evidence']),
      'layers' => sanitize_deep(payload['layers'])
    }
  end

  def sanitize_deep(value)
    case value
    when Hash then value.transform_values { |inner| sanitize_deep(inner) }
    when Array then value.map { |inner| sanitize_deep(inner) }
    when String then sanitize(value)
    else value
    end
  end

  def scan!(session)
    mark!(status: 'discovering')
    map = @connector.capabilities(provider: @connection.provider, session: session)
    raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'capabilities payload is not a hash') unless map.is_a?(Hash)

    schemas = quote_schemas(map)

    # DENTRO DO LOCK, com a linha recarregada: as duas chamadas acima levam segundos, e nesse tempo
    # o polling de cotação escreve `insurers_pending_auth` no mesmo jsonb (`merge_metadata!`).
    # Gravar o retrato de antes apagaria isso em silêncio — a classe de defeito que o lock de
    # `apply_status!` já evita, e que esta escrita repetia (Codex, 10/09/2026).
    @connection.with_lock do
      @connection.update!(
        status: 'ready',
        capabilities: map,
        capabilities_version: map['scanned_at'],
        last_capability_scan_at: Time.current,
        metadata: com_schemas(@connection.metadata.to_h, schemas)
      )
    end
  end

  # O FORMULÁRIO DE CADA RAMO vem junto da varredura (entrega 2 para auto; chat#591 para os outros):
  # é o `quote/schema` do adapter, guardado na conexão para a ferramenta montar os parâmetros do
  # especialista sem chamada por turno.
  # -> { produto => schema } do que o adapter respondeu AGORA. Produto que não respondeu fica de fora,
  # e aí fica o que a linha já tinha (mesclado por produto em `com_schemas`): um formulário velho é
  # melhor que nenhum, e a próxima sincronização tenta de novo.
  #
  # CUSTO: uma chamada por produto, sem sessão e sem portal (o schema é do código do adapter), cada
  # uma com o teto de leitura da conferência. Roda no `ScanJob`, fora de requisição web.
  def quote_schemas(map)
    produtos_do_mapa(map).each_with_object({}) do |produto, schemas|
      schemas[produto] = @connector.quote_schema(provider: @connection.provider, product: produto)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][insurance] quote_schema indisponivel na sincronizacao connection=#{@connection.id} " \
                        "produto=#{produto} #{e.class}")
    end
  end

  # Os ramos ATIVOS no mapa que a varredura acabou de ler (o mesmo filtro de
  # `consultar_produtos_cotacao`), mais auto sempre: auto é o formulário padrão da ferramenta, e
  # até a chat#591 era buscado em toda sincronização, com o ramo ativo ou não.
  def produtos_do_mapa(map)
    ativos = Array(map['products']).select { |produto| produto.is_a?(Hash) && produto['enabled'] }
    ([AUTO] + ativos.map { |produto| produto['product'].to_s }).compact_blank.uniq
  end

  # Mesclado POR PRODUTO sobre o que a linha tem agora: adapter mudo num produto não apaga o outro.
  def com_schemas(metadata, schemas)
    metadata.merge('quote_schemas' => metadata['quote_schemas'].to_h.merge(schemas))
  end

  # `failure:` só nos ERROS (auditoria da conexão, 05/11/2026). Antes daqui o erro gravava status e
  # `last_error` e deixava `last_failure` como a verificação anterior o deixou — nil, de quando estava
  # tudo bem —, e a tela, que decide pelo `actor`, não pedia nada a ninguém. Gravar a falha que o
  # adapter classificou (ou nada, quando ele não classificou) é o que faz a tela e o healthcheck lerem
  # o MESMO fato. Os estados transitórios não passam `failure:` e não tocam no diagnóstico.
  #
  # Com `failure:` a escrita vai DENTRO DO LOCK, com a linha recarregada, pelo mesmo motivo de
  # `apply_status!`: o polling de cotação escreve `insurers_pending_auth` no mesmo jsonb.
  def mark!(status:, error: nil, failure: :manter)
    atributos = { status: status, last_error: sanitize(error), last_healthcheck_at: Time.current }
    return @connection.tap { |connection| connection.update!(atributos) } if failure == :manter

    @connection.with_lock do
      @connection.update!(atributos.merge(
                            metadata: @connection.metadata.to_h.merge('last_failure' => failure_gravavel(failure))
                          ))
    end
    @connection
  end

  # O RASTRO que faltou em 25/10 e 02/11: a tabela guarda só o último estado, e cada verificação o
  # sobrescreve. Uma linha por sincronização que MUDA o estado, comparando o de antes do `authenticating`
  # com o de depois — o transitório do meio não conta. A causa é o código do adapter (`failure.cause`,
  # já sanitizado e cortado em `mark!`), não a mensagem do portal. Sem migration: o log do worker já
  # vai para o CloudWatch. Roda no `ensure` de `call`, então não pode levantar.
  def registrar_mudanca(anterior)
    atual = @connection.status
    return if anterior == atual

    falha = @connection.last_failure
    Rails.logger.info({ evento: 'insurance.connection.status', connection_id: @connection.id,
                        account_id: @connection.account_id, de: anterior, para: atual,
                        causa: falha.is_a?(Hash) ? falha['cause'] : nil }.to_json)
  end

  # Esgotar a espera pelo login de OUTRO processo não é notícia do portal: o diagnóstico gravado (um
  # `sessions_full`, por exemplo) continua sendo o fato mais recente, e o login do outro ainda vai gravar
  # o seu. Os demais erros trazem a falha que o adapter classificou, ou nada.
  def diagnostico_do_erro(erro)
    return :manter if erro.causa == :espera_do_login

    erro.details.to_h['failure']
  end

  # Só Hash é diagnóstico: um adapter que mandasse texto no lugar viraria `last_failure` String, e a
  # tela e o healthcheck leem chaves dele.
  def failure_gravavel(failure)
    failure.is_a?(Hash) && failure.present? ? sanitize_deep(failure) : nil
  end

  def sanitize(message)
    return nil if message.blank?

    message.to_s.gsub(EMAIL, '<email>').gsub(LONG_TOKEN, '<redacted>').truncate(160)
  end
end
