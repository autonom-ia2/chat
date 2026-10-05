# Marks the conversation of an incoming message with the campaign it answers (#1002, PRD D14).
# Enqueued by CampaignJourney::ReplyMarkListener; the rules live in CampaignJourney::ReplyMarker.
class CampaignJourney::ReplyMarkJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.includes(:inbox, conversation: :contact).find_by(id: message_id)
    return if message.blank?

    CampaignJourney::ReplyMarker.new(message).perform
  end
end
