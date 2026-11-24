# #3063 (item 2): sends the WhatsApp Oficial and SMS recipients whose postponement (limit per customer or sending hours)
# is due. Enqueued by Autonomia::RitmoDeEnvio::VarreduraJob. A paused campaign (CampaignPause) waits; two runs for the
# same campaign never overlap, nor with the rest of the two versions (CampaignJourney::EnvioSozinho: the second one just
# leaves).
class CampaignJourney::RetomarAdiadosJob < ApplicationJob
  queue_as :low

  SERVICOS = {
    'Whatsapp' => 'Whatsapp::OneoffCampaignService',
    'Sms' => 'Sms::OneoffSmsCampaignService',
    'Twilio SMS' => 'Twilio::OneoffSmsCampaignService'
  }.freeze

  def perform(campaign_id)
    campaign = Campaign.find_by(id: campaign_id)
    servico = SERVICOS[campaign&.inbox&.inbox_type]
    return if servico.nil? || pausada?(campaign)

    CampaignJourney::EnvioSozinho.sozinho(campaign) { servico.constantize.new(campaign: campaign).retomar_adiados }
  end

  private

  def pausada?(campaign)
    CampaignPause.in_effect.exists?(pausable_type: 'Campaign', pausable_id: campaign.id)
  end
end
