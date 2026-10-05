# The WhatsApp Oficial campaign message in the conversation (#1002, PRD D20, §6.11, P2). After
# Meta accepted a template for an audience campaign, the message is recorded in the contact's
# conversation of that inbox, as the WhatsApp flow would find or open it:
#
# - outgoing message with the text the person received (recipient.message_content);
# - source_id = the id Meta returned, so the status webhook updates delivered/read on it and
#   Base::SendOnChannelService never sends it again (a message with a source_id "came from the
#   channel" and is skipped by SendReplyJob);
# - additional_attributes campaign_id + campaign_template_name for the bubble label.
#
# It writes no campaign mark (D14: the mark only comes with a reply). Best effort: the recipient
# was already sent; a failure here is logged and never changes the recipient.
class CampaignJourney::SentMessageRecorder
  def initialize(campaign:, recipient:, destination:)
    @campaign = campaign
    @recipient = recipient
    @destination = destination
    @inbox = campaign.inbox
  end

  def perform
    source_id = @recipient.source_id
    return if source_id.blank? || Message.exists?(inbox_id: @inbox.id, source_id: source_id)

    conversation_for(contact_inbox).messages.create!(message_attributes(source_id))
  rescue StandardError => e
    Rails.logger.error "[CampaignJourney] campaign=#{@campaign.id} recipient=#{@recipient.id} message not recorded: #{e.class}"
    nil
  end

  private

  def message_attributes(source_id)
    {
      account_id: @campaign.account_id, inbox_id: @inbox.id, message_type: :outgoing, content_type: :text,
      content: @recipient.message_content.presence || @campaign.message, source_id: source_id, status: :sent,
      sender: @campaign.sender,
      additional_attributes: { campaign_id: @campaign.id, campaign_template_name: @campaign.template_params.to_h['name'] }
    }
  end

  # The identity the template went to; else the contact's latest identity in the inbox (where its
  # replies land); else a new one, as the WhatsApp flow creates it.
  def contact_inbox
    identities = ContactInbox.where(inbox_id: @inbox.id, contact_id: @recipient.contact_id)
    identities.find_by(source_id: destination_source_id) || identities.order(:id).last ||
      ContactInboxBuilder.new(contact: @recipient.contact, inbox: @inbox, source_id: destination_source_id).perform
  end

  def destination_source_id
    @destination.to_s.delete('+')
  end

  # Same reuse rule as Whatsapp::IncomingMessageBaseService#set_conversation.
  def conversation_for(contact_inbox)
    conversations = contact_inbox.conversations
    existing = @inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    existing || ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end
end
