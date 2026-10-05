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

    recipient = answered_recipient
    return false if recipient.blank?

    CampaignJourney::CampaignMarks.mark!(@conversation, recipient[:campaign])
  end

  private

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
    recipient && { campaign: recipient.campaign, sent_at: recipient.sent_at }
  end

  def whatsapp_api_candidate
    recipient = WhatsappApiCampaignRecipient.includes(:whatsapp_api_campaign)
                                            .where(account_id: @message.account_id, inbox_id: @message.inbox_id, contact_id: @contact.id)
                                            .sent.where(sent_at: window)
                                            .order(sent_at: :desc).first
    recipient && { campaign: recipient.whatsapp_api_campaign, sent_at: recipient.sent_at }
  end

  def email_candidate
    email = @contact.email.to_s.strip.downcase
    return if email.blank?

    recipient = EmailCampaignRecipient.joins(:email_campaign).includes(:email_campaign)
                                      .merge(email_campaigns_replying_to_inbox)
                                      .where('LOWER(email_campaign_recipients.email) = ?', email)
                                      .where(sent_at: window)
                                      .order(sent_at: :desc).first
    recipient && { campaign: recipient.email_campaign, sent_at: recipient.sent_at }
  end

  def email_campaigns_replying_to_inbox
    reply_identities = EmailSenderIdentity.where(account_id: @message.account_id, reply_to_inbox_id: @message.inbox_id).select(:id)
    direct = EmailCampaign.where(account_id: @message.account_id, delivery_mode: :direct_inbox, sender_inbox_id: @message.inbox_id)
    via_domain = EmailCampaign.where(account_id: @message.account_id, delivery_mode: :ses, sender_identity_id: reply_identities)
    direct.or(via_domain)
  end
end
