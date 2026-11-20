# #3063 (item 2): sends the WhatsApp Oficial and SMS recipients whose postponement (limit per customer or sending hours)
# is due. Enqueued by Autonomia::RitmoDeEnvio::VarreduraJob. A paused campaign (CampaignPause) waits; two runs for the
# same campaign never overlap (the advisory lock is per campaign; the second one just leaves).
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

    sozinho(campaign) { servico.constantize.new(campaign: campaign).retomar_adiados }
  end

  private

  def pausada?(campaign)
    CampaignPause.in_effect.exists?(pausable_type: 'Campaign', pausable_id: campaign.id)
  end

  def sozinho(campaign)
    chave = "campaign_journey:retomar_adiados:#{campaign.id}"
    conexao = ActiveRecord::Base.connection
    return unless conexao.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{conexao.quote(chave)}, 0))")

    begin
      yield
    ensure
      conexao.select_value("SELECT pg_advisory_unlock(hashtextextended(#{conexao.quote(chave)}, 0))")
    end
  end
end
