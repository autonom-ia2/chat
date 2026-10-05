# The WhatsApp Oficial campaign message in the conversation (#1002, PRD D20, §6.11, P2), for
# campaigns linked to an audience. No conversation is ever created for it: a campaign to
# thousands of people must not fire thousands of conversation_created events (automations,
# webhooks, customers' n8n) nor fill the conversation list.
#
# - At send (#record_at_send): after Meta accepted the template, the message goes into the
#   contact's unresolved conversation of the inbox (same reuse rule as the WhatsApp flow) when
#   there is one; otherwise nothing is written.
# - At reply (#record_at_reply, from CampaignJourney::ReplyMarker): the reply's conversation was
#   created by the normal flow; if it does not have the message yet, it is inserted with
#   created_at = the send time and the recipient's status, before the mark. It is a backfill of a
#   past message, so it carries content_attributes.history_import — the fork's existing guard that
#   skips every new-message side effect (events, webhooks, SendReplyJob), as for WhatsApp history.
#
# Both: outgoing, the text the person received, source_id = Meta's id (the status webhook updates
# it; Base::SendOnChannelService never sends a message with a source_id), additional_attributes
# campaign_id + campaign_template_name. Idempotent by inbox + source_id. No campaign mark here
# (D14). Best effort: a failure is logged and never changes the recipient.
class CampaignJourney::SentMessageRecorder
  MESSAGE_STATUSES = %w[sent delivered read].freeze

  def initialize(campaign:, recipient:)
    @campaign = campaign
    @recipient = recipient
    @inbox = campaign.inbox
  end

  def record_at_send(destination)
    return if recorded?

    conversation = existing_conversation(destination)
    conversation&.messages&.create!(message_attributes)
  rescue StandardError => e
    log_failure(e)
  end

  def record_at_reply(conversation)
    return if recorded?

    sent_at = @recipient.sent_at
    conversation.messages.create!(
      message_attributes.merge(created_at: sent_at, updated_at: sent_at, status: message_status,
                               content_attributes: { history_import: true })
    )
  rescue StandardError => e
    log_failure(e)
  end

  private

  def recorded?
    @recipient.source_id.blank? || Message.exists?(inbox_id: @inbox.id, source_id: @recipient.source_id)
  end

  def message_attributes
    {
      account_id: @campaign.account_id, inbox_id: @inbox.id, message_type: :outgoing, content_type: :text,
      content: @recipient.message_content.presence || @campaign.message, source_id: @recipient.source_id, status: :sent,
      sender: @campaign.sender,
      additional_attributes: { campaign_id: @campaign.id, campaign_template_name: @campaign.template_params.to_h['name'] }
    }
  end

  def message_status
    MESSAGE_STATUSES.include?(@recipient.status) ? @recipient.status : 'sent'
  end

  # The identity the template went to, else the contact's latest identity in the inbox; then the
  # conversation Whatsapp::IncomingMessageBaseService#set_conversation would reuse. Never creates.
  def existing_conversation(destination)
    identities = ContactInbox.where(inbox_id: @inbox.id, contact_id: @recipient.contact_id)
    contact_inbox = identities.find_by(source_id: destination.to_s.delete('+')) || identities.order(:id).last
    return if contact_inbox.blank?

    conversations = contact_inbox.conversations
    @inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
  end

  def log_failure(error)
    Rails.logger.error "[CampaignJourney] campaign=#{@campaign.id} recipient=#{@recipient.id} message not recorded: #{error.class}"
    nil
  end
end
