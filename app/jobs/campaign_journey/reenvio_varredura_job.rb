# #3101: CampaignJourney::Reenvio::Varredura a cada 15 minutos (config/schedule.yml).
class CampaignJourney::ReenvioVarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    CampaignJourney::Reenvio::Varredura.rodar
  end
end
