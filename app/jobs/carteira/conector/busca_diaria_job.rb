# A busca de todo dia no conector (E7, #2900; config/schedule.yml).
#
# Sem argumento (a rotina): põe na fila um job por conta que ligou "Buscar novos seguros todo dia" e tem o Agger, cada um
# ESPACO depois do anterior. Nunca todas no mesmo minuto: cada busca chama a plataforma da corretora com o login dela.
#
# Com o id da conta: começa a busca dos últimos dias (Carteira::Conector::Sincronizar.diaria), que entra sozinha na
# carteira. A conta que já tem uma busca de todo dia andando fica com ela (a parada há muito tempo é retomada). A conta
# cujo login o Agger recusou não busca, e não fica calada: o resumo da carteira passa a dizer "O Agger pediu para você
# entrar de novo" (Carteira::Conector.pede_login?) no lugar do "Ligado". Uma conta que falha não para as outras. No
# registro, só o id da conta e a classe do erro.
class Carteira::Conector::BuscaDiariaJob < ApplicationJob
  queue_as :scheduled_jobs
  ESPACO = 20.seconds

  def perform(account_id = nil)
    return buscar(Account.find_by(id: account_id)) if account_id

    Carteira::Conector::BuscaDiaria.contas.order(:id).pluck(:id).each_with_index do |id, indice|
      self.class.set(wait: indice * ESPACO).perform_later(id)
    end
  end

  private

  def buscar(account)
    return if account.nil?
    return Carteira::Conector::Sincronizar.diaria(account) if Carteira::Conector.ligado?(account)

    motivo = Carteira::Conector.pede_login?(account) ? 'pede_login' : 'desligado'
    Rails.logger.info("[carteira][conector][diaria] account=#{account.id} #{motivo}")
  rescue StandardError => e
    Rails.logger.warn("[carteira][conector][diaria] account=#{account.id} #{e.class.name}")
  end
end
