# A busca de todo dia no conector (E7, #2900; config/schedule.yml): para cada conta que ligou "Buscar novos seguros todo
# dia" e tem o Agger pronto, começa a busca dos últimos dias (Carteira::Conector::Sincronizar.diaria), que entra sozinha
# na carteira. Cada conta anda no seu job; uma conta que falha não para as outras. A conta que já tem uma busca andando
# fica com ela.
class Carteira::Conector::BuscaDiariaJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Carteira::Conector::BuscaDiaria.contas.find_each do |account|
      next unless Carteira::Conector.ligado?(account)

      Carteira::Conector::Sincronizar.diaria(account)
    rescue StandardError => e
      Rails.logger.warn("[carteira][conector][diaria] account=#{account.id} #{e.class.name}")
    end
  end
end
