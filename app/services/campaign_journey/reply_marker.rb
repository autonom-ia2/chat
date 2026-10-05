# "Respondeu" (#1002, PRD §8.3): a message received from the contact in the same inbox up to 72h
# after the send. The reply marks its conversation with the campaign that was answered
# (CampaignJourney::CampaignMarks); nothing is written at send time (K2).
#
# - WhatsApp Oficial: campaign_recipients (Enterprise) of the contact in the inbox.
# - WhatsApp API: whatsapp_api_campaign_recipients of the contact in the inbox.
# - E-mail: email_campaign_recipients with the contact's e-mail, of a campaign whose replies go to
#   the inbox (sender inbox in direct mode, reply-to inbox of the verified domain in SES mode).
#
# When several campaigns were sent in the window, the most recent send is the one answered.
# WhatsApp Oficial audience campaigns also get their campaign message in the reply's conversation
# first (CampaignJourney::SentMessageRecorder#record_at_reply), since the send creates none.
class CampaignJourney::ReplyMarker
  REPLY_WINDOW = 72.hours
  WHATSAPP_RECIPIENT_STATUSES = %w[sent delivered read].freeze

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @contact = @conversation&.contact
  end

  def perform
    return false unless markable?

    answered = answered_recipient
    return false if answered.blank?

    record_campaign_message(answered)
    CampaignJourney::CampaignMarks.mark!(@conversation, answered[:campaign])
  end

  private

  # WhatsApp Oficial audience campaigns: the campaign message goes into the reply's conversation
  # before the mark, when the send did not find a conversation to record it in (P2).
  def record_campaign_message(answered)
    recipient = answered[:recipient]
    # Only the WhatsApp Oficial candidate carries its recipient.
    return unless recipient && CampaignAudienceLink.for_campaign(answered[:campaign])

    CampaignJourney::SentMessageRecorder.new(campaign: answered[:campaign], recipient: recipient).record_at_reply(@conversation)
  end

  def markable?
    @message.incoming? && !@message.private? && @contact.present?
  end

  def answered_recipient
    candidates.compact.max_by { |candidate| candidate[:sent_at] }
  end

  def candidates
    inbox = @message.inbox
    return [email_candidate] if inbox.email?
    return [whatsapp_api_candidate] if inbox.api?
    return [whatsapp_candidate] if inbox.whatsapp?

    []
  end

  def window
    (@message.created_at - REPLY_WINDOW)..@message.created_at
  end

  def whatsapp_candidate
    return unless defined?(CampaignRecipient)

    recipient = CampaignRecipient.includes(:campaign)
                                 .where(account_id: @message.account_id, inbox_id: @message.inbox_id, contact_id: @contact.id)
                                 .where(status: WHATSAPP_RECIPIENT_STATUSES, sent_at: window)
                                 .order(sent_at: :desc).first
    recipient && { campaign: recipient.campaign, sent_at: recipient.sent_at, recipient: recipient }
  end

  def whatsapp_api_candidate
    recipient = WhatsappApiCampaignRecipient.includes(:whatsapp_api_campaign)
                                            .where(account_id: @message.account_id, inbox_id: @message.inbox_id, contact_id: @contact.id)
                                            .sent.where(sent_at: window)
                                            .order(sent_at: :desc).first
    recipient && { campaign: recipient.whatsapp_api_campaign, sent_at: recipient.sent_at }
  end

  # The recipient is the contact itself when it carries contact_id (audience recipients, #999).
  # Without contact_id it is matched by e-mail (case-insensitive) and only when exactly one contact
  # of the account has that address — otherwise the reply could be someone else's.
  def email_candidate
    recipient = email_recipients.order(sent_at: :desc).first
    return if recipient.blank? || !same_person?(recipient)

    { campaign: recipient.email_campaign, sent_at: recipient.sent_at }
  end

  def email_recipients
    scope = EmailCampaignRecipient.joins(:email_campaign).includes(:email_campaign)
                                  .merge(email_campaigns_replying_to_inbox).where(sent_at: window)
    by_email = contact_email.present? ? scope.where('LOWER(email_campaign_recipients.email) = ?', contact_email) : scope.none
    return by_email unless recipient_contact_column?

    by_contact = scope.where(contact_id: @contact.id)
    contact_email.present? ? by_contact.or(by_email.where(contact_id: nil)) : by_contact
  end

  def same_person?(recipient)
    return true if recipient_contact_column? && recipient.contact_id.present?
    return true if Contact.where(account_id: @message.account_id).where('LOWER(email) = ?', contact_email).limit(2).count == 1

    Rails.logger.info "[CampaignJourney] reply not marked: e-mail shared by several contacts (recipient=#{recipient.id})"
    false
  end

  def contact_email
    @contact_email ||= @contact.email.to_s.strip.downcase
  end

  # email_campaign_recipients.contact_id arrives with #999; until then recipients match by e-mail.
  def recipient_contact_column?
    EmailCampaignRecipient.column_names.include?('contact_id')
  end

  def email_campaigns_replying_to_inbox
    reply_identities = EmailSenderIdentity.where(account_id: @message.account_id, reply_to_inbox_id: @message.inbox_id).select(:id)
    direct = EmailCampaign.where(account_id: @message.account_id, delivery_mode: :direct_inbox, sender_inbox_id: @message.inbox_id)
    via_domain = EmailCampaign.where(account_id: @message.account_id, delivery_mode: :ses, sender_identity_id: reply_identities)
    direct.or(via_domain)
  end
end
