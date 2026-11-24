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
#   messages (#737) or is blocked (chat#2733) stays out of the total. The audience SMS badge
#   (`channels.sms`) must be on at send time; off → everyone skipped with CHANNEL_DISABLED_REASON.
# - D2: one `queued` CampaignRecipient per contact before the first SMS; after the run everyone
#   has a final status (CampaignJourney::RecipientTracking).
# - D5: refusal and block are read again right before each SMS → skipped "opted_out" / "blocked"
#   (Contact.campaign_refusal_now).
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
#
# #3099 (duas versões): who fell in version 2 gets its text (CampaignJourney::DuasVersoes#segunda); #enviar_resto sends
# the rest of the audience after the choice.
module CampaignJourney::SmsOneoffRecipients
  include CampaignJourney::RecipientTracking

  NO_PHONE_REASON = 'Contact has no phone number'.freeze
  CHANNEL_DISABLED_REASON = 'Canal SMS desligado no público'.freeze
  ORIGEM_DO_RITMO = 'campanha_sms'.freeze

  # #3099: the campaign already ran (the test); the rest, now with the chosen version, gets a queued recipient
  # (idempotent per campaign + contact) and is sent like the first run. The campaign stays completed.
  def enviar_resto
    return if sms_audience_link.blank? || !defined?(CampaignRecipient)

    contacts = CampaignJourney::AudienceContacts.contacts_for(sms_audience_link, channel: :sms)
    return skip_all_recipients(contacts, CHANNEL_DISABLED_REASON) unless audience_sms_enabled?

    insert_recipients(contacts, status: :queued)
    campaign.campaign_recipients.queued.where(adiado_ate: nil).includes(:contact)
            .find_each(batch_size: INSERT_BATCH_SIZE) { |recipient| process_sms_recipient(recipient) }
    fail_unprocessed_recipients
  end

  private

  # The audience SMS badge is read again: turned off after the first run, the postponed are skipped like the others.
  def retomar_destinatario(recipient)
    return recipient.mark_skipped!(CHANNEL_DISABLED_REASON) if sms_audience_link.present? && !audience_sms_enabled?

    process_sms_recipient(recipient)
  end

  def process_audience(audience_labels)
    return super if sms_audience_link.blank?
    return send_untracked unless defined?(CampaignRecipient)

    contacts = CampaignJourney::AudienceContacts.contacts_for(sms_audience_link, channel: :sms)
    return skip_all_recipients(contacts, CHANNEL_DISABLED_REASON) unless audience_sms_enabled?

    register_queued_recipients(contacts).each { |recipient| process_sms_recipient(recipient) }
    fail_unprocessed_recipients
  end

  def sms_audience_link
    return @sms_audience_link if defined?(@sms_audience_link)

    @sms_audience_link = CampaignAudienceLink.for_campaign(campaign)
  end

  def audience_sms_enabled?
    CampaignJourney::AudienceContacts.sms_enabled?(sms_audience_link.campaign_import)
  end

  def sms_message
    @sms_message ||= CampaignJourney::SmsMessage.new(
      campaign.message, campaign_import: sms_audience_link.campaign_import, defaults: sms_audience_link.variable_defaults
    )
  end

  # #3099: the text of this person's version (version 2 keeps its own default texts).
  def sms_message_for(contact)
    duas_versoes = @sms_duas_versoes ||= CampaignJourney::DuasVersoes.new(sms_audience_link)
    duas_versoes.versao_2?(contact.id) ? sms_message_segunda(duas_versoes.segunda) : sms_message
  end

  def sms_message_segunda(segunda)
    @sms_message_segunda ||= CampaignJourney::SmsMessage.new(
      segunda['message_body'], campaign_import: sms_audience_link.campaign_import, defaults: segunda['variable_defaults']
    )
  end

  def process_sms_recipient(recipient)
    contact = recipient.contact
    refusal = Contact.campaign_refusal_now(contact.id)
    return recipient.mark_skipped!(refusal) if refusal
    return recipient.mark_skipped!(NO_PHONE_REASON) if contact.phone_number.blank?

    content, missing = sms_message_for(contact).render_for(contact)
    return recipient.mark_skipped!(CampaignJourney::SmsMessage.missing_reason(missing)) if missing.any?

    # #3063: limit per customer and sending hours, right before the send.
    return if adiado_pelo_ritmo?(recipient, contact)

    recipient.update!(message_content: content)
    deliver_sms(recipient, contact.phone_number, content)
  rescue StandardError => e
    handle_unexpected_sms_error(recipient, e)
  end

  def deliver_sms(recipient, to, content)
    source_id = CampaignJourney::SmsSender.new(channel).deliver(to: to, body: content)
    accepted_by_provider << recipient.id
    mark_sms_sent(recipient, source_id)
    contar_no_ritmo(recipient, ORIGEM_DO_RITMO)
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
    return unless audience_sms_enabled?

    CampaignJourney::AudienceContacts.contacts_for(sms_audience_link, channel: :sms).find_each do |contact|
      next if Contact.campaign_refusal_now(contact.id) || contact.phone_number.blank?

      content, missing = sms_message_for(contact).render_for(contact)
      CampaignJourney::SmsSender.new(channel).deliver(to: contact.phone_number, body: content) if missing.empty?
    rescue StandardError => e
      Rails.logger.error "[CampaignJourney] sms campaign=#{campaign.id} contact=#{contact.id} #{e.class}"
    end
  end
end
