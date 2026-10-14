# Marks the conversation of an incoming message with the campaign it answers (#1002, PRD D14).
# Enqueued by CampaignJourney::ReplyMarkListener; the rules live in CampaignJourney::ReplyMarker.
# #1449: depois da marca (e da mensagem da campanha gravada na resposta), a primeira resposta a uma campanha do WhatsApp
# vai ao modelo para saber se é pedido de parar (CampaignJourney::OptOutReply).
class CampaignJourney::ReplyMarkJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.includes(:inbox, conversation: :contact).find_by(id: message_id)
    return if message.blank?

    CampaignJourney::ReplyMarker.new(message).perform
    CampaignJourney::OptOutReplyJob.perform_later(message.id) if CampaignJourney::OptOutReply.new(message).applicable?
  end
end
