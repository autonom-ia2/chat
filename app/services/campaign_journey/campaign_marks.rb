# Campaign mark in the CRM (#1002, PRD D14, §6.7 and §8.3): a campaign becomes an origin touch
# on the conversation through the same mechanism as Links and QR codes
# (Ctwa::CampaignBuilder.attribute!). The first touch stays the origin; a campaign that arrives
# later is appended to campaign_touches (K7). Idempotent per conversation + campaign: the
# builder dedups by source_id.
module CampaignJourney::CampaignMarks
  module_function

  WHATSAPP_SOURCE = 'campaign_whatsapp'.freeze
  EMAIL_SOURCE = 'campaign_email'.freeze
  SMS_SOURCE = 'campaign_sms'.freeze
  SOURCES = [WHATSAPP_SOURCE, EMAIL_SOURCE, SMS_SOURCE].freeze

  # campaign class => [source_type, <type> of the "campaign:<type>:<id>" source id, name attribute]
  KINDS = {
    'Campaign' => [WHATSAPP_SOURCE, 'whatsapp', :title],
    'WhatsappApiCampaign' => [WHATSAPP_SOURCE, 'whatsapp_api', :title],
    'EmailCampaign' => [EMAIL_SOURCE, 'email', :name]
  }.freeze
  # A Chatwoot Campaign on an SMS inbox (#1004).
  SMS_KIND = [SMS_SOURCE, 'sms', :title].freeze

  def mark!(conversation, campaign)
    source_type, _type, name_attribute = kind_for(campaign)
    source_id = source_id_for(campaign)
    return false if marked?(conversation, source_id)

    Ctwa::CampaignBuilder.attribute!(
      conversation,
      source_id: source_id, source_type: source_type, headline: campaign.public_send(name_attribute)
    )
  end

  # "campaign:<type>:<id>", e.g. "campaign:sms:12".
  def source_id_for(campaign)
    "campaign:#{kind_for(campaign)[1]}:#{campaign.id}"
  end

  # "Responderam" of a campaign: conversations of the account marked with it (the mark is written
  # only on reply, D14). Same probe as the campaign filters (campaign_source_ids, trigram index).
  def replied_count(campaign)
    token = "%\"#{Conversation.sanitize_sql_like(source_id_for(campaign))}\"%"
    Conversation.where(account_id: campaign.account_id)
                .where("conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ?", token)
                .count
  end

  def kind_for(campaign)
    return SMS_KIND if campaign.is_a?(Campaign) && sms_inbox?(campaign.inbox)

    KINDS.fetch(campaign.class.name)
  end

  # Bandwidth SMS or Twilio SMS (a Twilio inbox can also be WhatsApp).
  def sms_inbox?(inbox)
    inbox.present? && (inbox.sms? || (inbox.twilio? && inbox.channel.sms?))
  end

  # Cheap in-memory check so repeated replies never take the row lock of the builder.
  def marked?(conversation, source_id)
    Array(conversation.additional_attributes.to_h['campaign_source_ids']).include?(source_id)
  end
end
