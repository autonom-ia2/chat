# A rotina da renovação da carteira de seguros (E5, #2898), a cada hora (config/schedule.yml): enfileira um
# Carteira::Renovacao::DaContaJob por conta que já escolheu onde ficam as renovações. A busca dos seguros fica no job
# de cada conta: uma carteira grande não atrasa as outras. De hora em hora porque o dia vira no fuso de cada conta; a
# passada que não acha seguro novo é uma leitura pelo índice e mais nada.
class Carteira::Renovacao::RotinaJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Carteira::RenovacaoConfig.where.not(pipeline_id: nil).where.not(stage_id: nil).in_batches do |lote|
      lote.pluck(:account_id).each { |account_id| Carteira::Renovacao::DaContaJob.perform_later(account_id) }
    end
  end
end
