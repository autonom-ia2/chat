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

  # Estados que vale a pena verificar. `auth_required` e `human_required` ficam DE FORA: são estados
  # que dependem de uma pessoa, e insistir de 30 em 30 minutos com uma credencial que o portal já
  # recusou é o caminho para bloquear a conta da corretora.
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

  def perform
    ::Autonomia::Insurance::Connection.where(status: CHECKABLE).find_each(batch_size: BATCH_SIZE) do |connection|
      check(connection)
    end
    presas.find_each(batch_size: BATCH_SIZE) { |connection| check(connection) }
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
  # consultável na tela, que é o que o corretor precisa ver.
  def check(connection)
    return unless ::Autonomia::Insurance::Config.enabled?(connection.account)

    ::Autonomia::Insurance::Connections::Sync.new(connection, scan_capabilities: false).call
  rescue StandardError => e
    # Uma conexão problemática não pode impedir a verificação das outras.
    Rails.logger.warn("[autonomia][insurance] healthcheck failed connection=#{connection.id} #{e.class}")
    nil
  end
end
