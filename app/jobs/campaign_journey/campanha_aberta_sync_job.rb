# #2717: alguém entrou, saiu ou mudou no público (CampaignImportRow). Cada campanha de e-mail aberta ligada a ele, enviando
# ou pausada, sincroniza a lista: quem entrou recebe pela régua de sempre, o pendente de quem saiu é apagado.
class CampaignJourney::CampanhaAbertaSyncJob < ApplicationJob
  queue_as :low

  def perform(campaign_import_id)
    return unless EmailCampaigns::Config.enabled?

    campanhas_abertas(campaign_import_id).find_each { |campanha| CampaignJourney::CampanhaAberta.sincronizar!(campanha) }
  end

  private

  def campanhas_abertas(campaign_import_id)
    ligadas = CampaignAudienceLink.where(campaign_type: EmailCampaign.name, campaign_import_id: campaign_import_id).select(:campaign_id)
    EmailCampaign.where(id: ligadas, aberta: true, status: %i[sending paused])
  end
end
