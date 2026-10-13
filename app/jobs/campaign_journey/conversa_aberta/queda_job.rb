# Manda o modelo da campanha para quem o texto livre não alcançou (131047, #1335). Uma vez só por pessoa: a linha da
# entrega é marcada antes de enviar, sob trava, e um segundo aviso igual não faz nada.
class CampaignJourney::ConversaAberta::QuedaJob < ApplicationJob
  queue_as :low

  def perform(delivery_id)
    delivery = CampaignFreeTextDelivery.find_by(id: delivery_id)
    return if delivery.nil?

    recipient = marcar_queda(delivery)
    return if recipient.nil?

    Whatsapp::OneoffCampaignService.new(campaign: delivery.campaign).enviar_modelo!(recipient)
  end

  private

  def marcar_queda(delivery)
    delivery.with_lock do
      next if delivery.fell_back?

      delivery.update!(fell_back_at: Time.current)
      CampaignRecipient.find_by(id: delivery.campaign_recipient_id, campaign_id: delivery.campaign_id)
    end
  end
end
