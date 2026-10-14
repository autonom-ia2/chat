# #1460 — cria a próxima vez de cada lembrete que repete. Só olha séries ativas sem vez pendente: a vez marcada
# passou (o DueProcessor avisou) ou foi feita, e a próxima precisa nascer. Uma série com problema não para as outras.
class Crm::FollowUpSeriesMaterializerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless Crm::Config.enabled?

    waiting_series.find_each do |series|
      Crm::FollowUps::SeriesMaterializer.new(series).perform
    rescue StandardError => e
      Rails.logger.error("[crm][follow_up_series] series_id=#{series.id} error_class=#{e.class.name} message=#{e.message}")
    end
  end

  private

  def waiting_series
    pending_series_ids = Crm::FollowUp.pending.where.not(series_id: nil).select(:series_id)
    Crm::FollowUpSeries.active.where.not(id: pending_series_ids)
  end
end
