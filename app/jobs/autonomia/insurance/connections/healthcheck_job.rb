# PING periódico das conexões com o portal.
#
# Antes disto, "Última verificação" só mudava quando alguém clicava em Conectar, Reconectar ou
# Atualizar configuração — na prática, horas de atraso entre a conexão morrer e alguém descobrir.
# O corretor via "Autenticada" enquanto a cotação já estava quebrada.
#
# O ping é BARATO de propósito: reusa a sessão guardada e faz uma sonda autenticada no portal
# (`connection_status`), sem redescobrir ramos e seguradoras — isso é a "Última descoberta", outra
# coisa, muito mais pesada, que continua sendo manual.
#
# Só é seguro pingar com esta frequência porque a sessão passou a ser única por conexão (#330). Com
# o desenho anterior, cada verificação fazia login e invalidava a sessão da cotação em andamento:
# pingar mais vezes por dia teria QUEBRADO mais cotações, não menos.
class Autonomia::Insurance::Connections::HealthcheckJob < ApplicationJob
  queue_as :scheduled_jobs

  # Estados que vale a pena verificar a cada ciclo. `auth_required` e `human_required` ficam fora desta
  # lista: insistir de 30 em 30 minutos com uma credencial que o portal já recusou é o caminho para
  # bloquear a conta da corretora. A exceção é o `auth_required` que o adapter diz NÃO ser da
  # corretora — ver `recusas_sem_dono` e `RETRY_AUTH_AFTER`.
  CHECKABLE = %w[ready degraded offline].freeze
  BATCH_SIZE = 100

  # REDE DE SEGURANÇA. Estado transitório é para durar segundos: um processo que morre no meio
  # (proxy cortando, deploy trocando a instância, job perdido) deixa a conexão parada nele para
  # sempre — e a tela desabilita os botões justamente nesses estados, então o corretor fica sem
  # conseguir nem tentar de novo. Aconteceu em 06/09/2026 com a conta 16.
  #
  # Nada aqui adivinha o que houve: a conexão só é RE-SINCRONIZADA, e o resultado dessa
  # sincronização é que decide o estado. Se estiver tudo bem, volta a `ready` sozinha.
  STUCK_AFTER = 10.minutes

  # Presa em `discovering` é uma VARREDURA que morreu, e é ela que se refaz. Re-sincronizar sem varrer
  # devolvia `ready` sem capacidades nem formulários, e toda cotação de auto era recusada até alguém
  # clicar em Atualizar configuração (auditoria da conexão, 05/11/2026, achado 17).
  VARRENDO = 'discovering'.freeze

  # `auth_required` QUE NÃO É DA CORRETORA volta a ser tentado, a cada 60 a 90 minutos (auditoria da
  # conexão, 05/11/2026). Só quando o adapter AFIRMA que a ação não é dela — `last_failure.actor`
  # presente e diferente de `broker` (sessão recusada depois de renovar, por exemplo). Sem
  # classificação, a linha fica parada como antes: não dá para provar que não é senha recusada, e
  # repetir login com senha errada de hora em hora é o que a regra de cima existe para impedir.
  # Deixar tudo fora parou a conexão da conta 16 de 25/10 a 01/11. Se a tentativa voltar como senha
  # recusada, ela traz `actor: broker` e a conexão sai desta lista sozinha.
  RETRY_AUTH_AFTER = 1.hour
  ACAO_DA_CORRETORA = 'broker'.freeze

  def perform
    ::Autonomia::Insurance::Connection.where(status: CHECKABLE).find_each(batch_size: BATCH_SIZE) do |connection|
      check(connection)
    end
    presas.find_each(batch_size: BATCH_SIZE) { |connection| check(connection, varrer: connection.status == VARRENDO) }
    recusas_sem_dono.find_each(batch_size: BATCH_SIZE) { |connection| check(connection) }
  end

  def recusas_sem_dono
    ::Autonomia::Insurance::Connection
      .where(status: 'auth_required')
      .where('last_healthcheck_at IS NULL OR last_healthcheck_at < ?', RETRY_AUTH_AFTER.ago)
      .where("metadata -> 'last_failure' ->> 'actor' IS NOT NULL")
      .where("metadata -> 'last_failure' ->> 'actor' <> ?", ACAO_DA_CORRETORA)
  end

  # Transitória e parada há tempo demais. A margem é generosa de propósito: a descoberta completa
  # leva ~25 s, e qualquer transitório legítimo termina muito antes de dez minutos.
  def presas
    ::Autonomia::Insurance::Connection
      .where(status: ::Autonomia::Insurance::Connection::TRANSIENT_STATUSES)
      .where(updated_at: ...STUCK_AFTER.ago)
  end

  private

  # `Sync` com `scan_capabilities: false` é exatamente o ping: resolve a sessão (reusa ou renova),
  # consulta o portal, grava status e `last_healthcheck_at`, e NUNCA levanta — falha vira estado
  # consultável na tela, que é o que o corretor precisa ver. `varrer:` só para a varredura presa.
  def check(connection, varrer: false)
    return unless ::Autonomia::Insurance::Config.enabled?(connection.account)

    ::Autonomia::Insurance::Connections::Sync.new(connection, scan_capabilities: varrer).call
  rescue StandardError => e
    # Uma conexão problemática não pode impedir a verificação das outras.
    Rails.logger.warn("[autonomia][insurance] healthcheck failed connection=#{connection.id} #{e.class}")
    nil
  end
end
