# The WhatsApp Oficial and SMS (#1004) campaign message in the conversation (#1002, PRD D20,
# §6.11, P2), for campaigns linked to an audience. No conversation is ever created for it: a
# campaign to thousands of people must not fire thousands of conversation_created events
# (automations, webhooks, customers' n8n) nor fill the conversation list.
#
# - At send (#record_at_send): after the provider accepted the message, it goes into the
#   contact's unresolved conversation of the inbox (same reuse rule as the WhatsApp flow) when
#   there is one; otherwise nothing is written.
# - At reply (#record_at_reply, from CampaignJourney::ReplyMarker): the reply's conversation was
#   created by the normal flow; if it does not have the message yet, it is inserted with
#   created_at = the send time and the recipient's status, before the mark. It is a backfill of a
#   past message, so it carries content_attributes.history_import — the fork's existing guard that
#   skips every new-message side effect (events, webhooks, SendReplyJob), as for WhatsApp history.
#
# Both: outgoing, the text the person received, source_id = the provider id (Meta, Twilio or
# Bandwidth; the status callback updates it; Base::SendOnChannelService never sends a message
# with a source_id), additional_attributes campaign_id (+ campaign_template_name on WhatsApp, or campaign_free_text for
# the written message of #1335; + campaign_template_enviado, the photo of the send, #1717).
# Idempotent by inbox + source_id. No campaign mark here (D14). Best effort: a failure is logged
# and never changes the recipient.
class CampaignJourney::SentMessageRecorder
  MESSAGE_STATUSES = %w[sent delivered read].freeze

  # free_text (#1335): a mensagem escrita da conversa aberta — sem nome de modelo, marcada como texto da campanha.
  # enviado (#1717): the photo of the send (Whatsapp::Templates::FotoDoEnvio), when the caller has it.
  def initialize(campaign:, recipient:, free_text: false, enviado: nil)
    @campaign = campaign
    @recipient = recipient
    @inbox = campaign.inbox
    @free_text = free_text
    @enviado = enviado
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
      # The text the person received already carries contact and audience values: it stays literal (#1021).
      literal_content: true,
      additional_attributes: campaign_attributes
    }
  end

  # campaign_id sempre (o robô do #1405 não assume conversa de campanha); o modelo só quando foi modelo.
  def campaign_attributes
    return { campaign_id: @campaign.id, campaign_free_text: true } if @free_text

    name = @campaign.template_params.to_h['name']
    { campaign_id: @campaign.id, campaign_template_name: name }.compact.merge(template_photo(name))
  end

  # #1717: the photo of what was sent, for the conversation to show it as it went out. It goes in its own key, never in
  # template_params: a message with template_params counts as a template send (Whatsapp::TemplateSendCount,
  # Whatsapp::Templates::Health, the service-message allowance), and the campaign recipient is already counted there.
  # At send it is the photo of this person's send; at reply (no send in hand) it is rebuilt from the campaign: products
  # from what the dispatch read, and a link whose variable was per person stays without an address.
  def template_photo(name)
    enviado = @enviado || campaign_photo
    name.present? && enviado.present? ? { campaign_template_enviado: enviado } : {}
  end

  def campaign_photo
    return unless @inbox.channel.is_a?(Channel::Whatsapp) && @campaign.template_params.present?

    Whatsapp::TemplateProcessorService.new(channel: @inbox.channel, template_params: @campaign.template_params)
                                      .foto_do_envio(catalogo: :guardado)
  end

  def message_status
    MESSAGE_STATUSES.include?(@recipient.status) ? @recipient.status : 'sent'
  end

  # The identity the template went to, else the contact's latest identity in the inbox; then the
  # conversation Whatsapp::IncomingMessageBaseService#set_conversation would reuse. Never creates.
  def existing_conversation(destination)
    identities = ContactInbox.where(inbox_id: @inbox.id, contact_id: @recipient.contact_id)
    contact_inbox = identities.find_by(source_id: source_ids_for(destination)) || identities.order(:id).last
    return if contact_inbox.blank?

    conversations = contact_inbox.conversations
    @inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
  end

  # WhatsApp identities are stored without "+", SMS ones (Twilio, Bandwidth) with it (#1004).
  def source_ids_for(destination)
    [destination.to_s, destination.to_s.delete('+')].uniq
  end

  def log_failure(error)
    Rails.logger.error "[CampaignJourney] campaign=#{@campaign.id} recipient=#{@recipient.id} message not recorded: #{error.class}"
    nil
  end
end
