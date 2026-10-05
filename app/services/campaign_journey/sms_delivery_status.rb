# Delivery callbacks of SMS campaign messages update the campaign recipient (#1004, PRD §8.8;
# M3 "entregue/falhou com motivo"), by modules prepended in config/initializers/campaign_journey.rb.
# Twilio: Chatwoot's callback code runs untouched after ours (it updates the conversation message).
# Bandwidth: Chatwoot's job never reached the conversation message on a delivery event (it looks
# the channel up by `to`, which is the customer on an outbound message, and builds
# Sms::DeliveryStatusService with `channel:` while the service takes `inbox:`); BandwidthCallback
# finds the inbox by the message owner (our number) and calls the service with it. Incoming
# messages keep Chatwoot's path.
#
# The recipient is found by the provider message id (campaign_recipients.source_id) within the
# inbox the callback belongs to. Statuses never go back (CampaignRecipient#update_from_whatsapp_status!,
# the same rule as WhatsApp: failed never overrides delivered). A failure carries the provider
# reason when there is one, through CampaignImports::SafeLogMessage (digit runs and tokens masked).
module CampaignJourney::SmsDeliveryStatus
  # Twilio's own titles for the most common SMS delivery errors
  # (https://www.twilio.com/docs/api/errors); other codes read "Error code: <code>".
  TWILIO_ERRORS = {
    '21610' => 'Recipient replied STOP (unsubscribed)',
    '30003' => 'Unreachable destination handset',
    '30004' => 'Message blocked',
    '30005' => 'Unknown destination handset',
    '30006' => 'Landline or unreachable carrier',
    '30007' => 'Message filtered by the carrier',
    '30008' => 'Unknown error'
  }.freeze

  module_function

  def apply(inbox:, source_id:, status:, code: nil, reason: nil)
    return unless defined?(CampaignRecipient) && inbox && source_id.present?

    recipient = CampaignRecipient.find_by(inbox_id: inbox.id, source_id: source_id)
    return if recipient.blank?

    recipient.update_from_whatsapp_status!(status: status, errors: [{ code: code&.to_s, error_user_msg: safe_reason(reason) }])
  rescue StandardError => e
    Rails.logger.error "[CampaignJourney] sms delivery status not applied: #{e.class}"
  end

  def safe_reason(reason)
    CampaignImports::SafeLogMessage.call(reason) if reason.present?
  end

  # Twilio StatusCallback (Twilio::DeliveryStatusService).
  module TwilioCallback
    STATUSES = { 'delivered' => 'delivered', 'failed' => 'failed', 'undelivered' => 'failed' }.freeze

    def perform
      apply_to_campaign_recipient
      super
    end

    private

    def apply_to_campaign_recipient
      status = STATUSES[params[:MessageStatus].to_s]
      return if status.nil? || twilio_channel.blank? || !twilio_channel.sms?

      CampaignJourney::SmsDeliveryStatus.apply(
        inbox: twilio_channel.inbox, source_id: params[:MessageSid], status: status,
        code: params[:ErrorCode].presence, reason: twilio_reason
      )
    end

    def twilio_reason
      code = params[:ErrorCode].to_s
      return if code.blank?

      params[:ErrorMessage].presence || TWILIO_ERRORS[code] || I18n.t('conversations.messages.delivery_status.error_code', error_code: code)
    end
  end

  # Bandwidth message-delivered / message-failed (Webhooks::SmsEventsJob). The channel is the
  # message owner (our number); `to` is the fallback.
  module BandwidthCallback
    STATUSES = { 'message-delivered' => 'delivered', 'message-failed' => 'failed' }.freeze

    def perform(params = {})
      event = params.to_h.with_indifferent_access
      status = STATUSES[event[:type].to_s]
      return super if status.nil?

      inbox = bandwidth_inbox(event)
      return if inbox.blank?

      apply_to_campaign_recipient(inbox, event, status)
      Sms::DeliveryStatusService.new(inbox: inbox, params: event).perform
    end

    private

    def bandwidth_inbox(event)
      channel = Channel::Sms.find_by(phone_number: event.dig(:message, :owner)) if event.dig(:message, :owner).present?
      channel ||= Channel::Sms.find_by(phone_number: event[:to]) if event[:to].present?
      channel&.inbox
    end

    def apply_to_campaign_recipient(inbox, event, status)
      reason = [event[:errorCode], event[:description]].compact_blank.join(' - ') if status == 'failed'
      CampaignJourney::SmsDeliveryStatus.apply(
        inbox: inbox, source_id: event.dig(:message, :id), status: status, code: event[:errorCode], reason: reason
      )
    end
  end
end
