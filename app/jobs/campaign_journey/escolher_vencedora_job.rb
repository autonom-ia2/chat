# #3099: escolhe a versão que vai para o resto das campanhas com duas versões (CampaignJourney::DuasVersoes::Escolha).
# Cron em config/schedule.yml, a cada 5 minutos. Só olha os links cujo resto ainda espera; uma campanha com problema
# vai ao log e não segura as outras.
class CampaignJourney::EscolherVencedoraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    CampaignAudienceLink.where(teste_estado: CampaignJourney::DuasVersoes::ESPERANDO_O_RESTO).find_each do |link|
      CampaignJourney::DuasVersoes::Escolha.new(link).decidir!
    rescue StandardError => e
      Rails.logger.error "[CampaignJourney::EscolherVencedoraJob] link=#{link.id} #{e.class}: #{e.message.truncate(200)}"
    end
  end
end
