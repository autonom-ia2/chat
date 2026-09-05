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

  def perform
    ::Autonomia::Insurance::Connection.where(status: CHECKABLE).find_each(batch_size: BATCH_SIZE) do |connection|
      check(connection)
    end
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
