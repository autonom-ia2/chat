# SMS campaigns of the journey (#1004, PRD §8.8; acceptance M3, D2, D4, D5, B1b). Prepended into
# Sms::OneoffSmsCampaignService (Bandwidth) and Twilio::OneoffSmsCampaignService by
# config/initializers/campaign_journey.rb; neither service is edited.
#
# Only campaigns linked to an audience (campaign_audience_links) take this path, with
# CAMPAIGN_JOURNEY_ENABLED on or off (otherwise they would send to no one). Label campaigns keep
# Chatwoot's code untouched (pure `super`), with the flag on or off.
#
# - Who receives: the audience's contacts by the phone rule (CampaignJourney::AudienceContacts,
#   same as WhatsApp: the row brought that mobile and the contact still has it); who refused
#   messages (#737) stays out of the total. The audience phone channel (`channels.whatsapp`, the
#   mobile badge) must be on at send time; off → everyone skipped with CHANNEL_DISABLED_REASON.
# - D2: one `queued` CampaignRecipient per contact before the first SMS; after the run everyone
#   has a final status (CampaignJourney::RecipientTracking).
# - D5: refusal is read again right before each SMS → skipped "opted_out".
# - B1b: tokens per person (CampaignJourney::SmsMessage); missing value without default →
#   skipped "falta empresa" / "falta <coluna>".
# - D4: provider refusal → failed with the provider's reason (CampaignJourney::SmsSender);
#   unexpected error before the provider accepted → failed "Unexpected error while sending
#   (<Class>)"; the others go on. Accepted → sent with the provider id as source_id (the status
#   callback updates delivered/failed, CampaignJourney::SmsDeliveryStatus).
# - M3/P2: the accepted SMS goes into the contact's existing conversation of the inbox
#   (CampaignJourney::SentMessageRecorder); no conversation is created; the reply's conversation
#   gets it later (CampaignJourney::ReplyMarker). Never sent twice: the message carries the
#   provider id, which Base::SendOnChannelService never sends.
#
# Without Enterprise (no CampaignRecipient) a linked campaign still sends to the audience, without
# per-recipient tracking.
module CampaignJourney::SmsOneoffRecipients
  include CampaignJourney::RecipientTracking

  OPTED_OUT_REASON = 'opted_out'.freeze
  NO_PHONE_REASON = 'Contact has no phone number'.freeze
  CHANNEL_DISABLED_REASON = 'Canal de celular desligado no público'.freeze

  private

  def process_audience(audience_labels)
    return super if sms_audience_link.blank?
    return send_untracked unless defined?(CampaignRecipient)

    contacts = CampaignJourney::AudienceContacts.contacts_for(sms_audience_link, channel: :sms)
    return skip_all_recipients(contacts, CHANNEL_DISABLED_REASON) unless audience_phone_enabled?

    register_queued_recipients(contacts).each { |recipient| process_sms_recipient(recipient) }
    fail_unprocessed_recipients
  end

  def sms_audience_link
    return @sms_audience_link if defined?(@sms_audience_link)

    @sms_audience_link = CampaignAudienceLink.for_campaign(campaign)
  end

  def audience_phone_enabled?
    CampaignJourney::AudienceContacts.whatsapp_enabled?(sms_audience_link.campaign_import)
  end

  def sms_message
    @sms_message ||= CampaignJourney::SmsMessage.new(
      campaign.message, campaign_import: sms_audience_link.campaign_import, defaults: sms_audience_link.variable_defaults
    )
  end

  def process_sms_recipient(recipient)
    contact = recipient.contact
    return recipient.mark_skipped!(OPTED_OUT_REASON) if Contact.opted_out.exists?(id: contact.id)
    return recipient.mark_skipped!(NO_PHONE_REASON) if contact.phone_number.blank?

    content, missing = sms_message.render_for(contact)
    return recipient.mark_skipped!(CampaignJourney::SmsMessage.missing_reason(missing)) if missing.any?

    recipient.update!(message_content: content)
    deliver_sms(recipient, contact.phone_number, content)
  rescue StandardError => e
    handle_unexpected_sms_error(recipient, e)
  end

  def deliver_sms(recipient, to, content)
    source_id = CampaignJourney::SmsSender.new(channel).deliver(to: to, body: content)
    accepted_by_provider << recipient.id
    mark_sms_sent(recipient, source_id)
    CampaignJourney::SentMessageRecorder.new(campaign: campaign, recipient: recipient).record_at_send(to)
  rescue CampaignJourney::SmsSender::Error => e
    recipient.mark_failed!(code: e.code, message: e.message)
  end

  def mark_sms_sent(recipient, source_id)
    recipient.mark_sent!(source_id)
  rescue StandardError => e
    keep_as_sent(recipient, source_id, e)
  end

  def handle_unexpected_sms_error(recipient, error)
    Rails.logger.error "[CampaignJourney] sms campaign=#{campaign.id} recipient=#{recipient.id} #{error.class}"
    return if accepted_by_provider.include?(recipient.id)

    recipient.mark_failed!(message: "Unexpected error while sending (#{error.class.name})")
  end

  # Open source build: same audience and tokens, no recipient rows.
  def send_untracked
    return unless audience_phone_enabled?

    CampaignJourney::AudienceContacts.contacts_for(sms_audience_link, channel: :sms).find_each do |contact|
      next if Contact.opted_out.exists?(id: contact.id) || contact.phone_number.blank?

      content, missing = sms_message.render_for(contact)
      CampaignJourney::SmsSender.new(channel).deliver(to: contact.phone_number, body: content) if missing.empty?
    rescue StandardError => e
      Rails.logger.error "[CampaignJourney] sms campaign=#{campaign.id} contact=#{contact.id} #{e.class}"
    end
  end
end
