# #3099: manda o resto do público com a versão escolhida (CampaignJourney::DuasVersoes::EnvioDoResto). Enfileirado por
# CampaignJourney::DuasVersoes#mandar_resto!, depois do commit da escolha (pelo cron ou pela pessoa).
class CampaignJourney::EnviarRestoJob < ApplicationJob
  queue_as :low

  def perform(link_id)
    link = CampaignAudienceLink.find_by(id: link_id)
    return if link.nil? || link.teste_estado != 'escolhida'

    CampaignJourney::DuasVersoes::EnvioDoResto.new(link).enviar!
  end
end
