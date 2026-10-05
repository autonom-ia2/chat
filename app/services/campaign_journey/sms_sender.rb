# Sends one SMS of a journey campaign through the inbox's own channel method (#1004) and returns
# the provider's message id, or raises Error with a readable reason (D4). Provider reasons pass
# through CampaignImports::SafeLogMessage (long digit runs such as phone numbers and token-like
# strings are masked, length capped) before they reach the recipient.
#
# - Twilio SMS: Channel::TwilioSms#send_message (it already asks Twilio for the StatusCallback);
#   the id is the message SID. A refusal keeps Twilio's code and message.
# - Bandwidth (Channel::Sms): Channel::Sms#send_message, the channel's public method for a message,
#   receives a CampaignJourney::SmsBandwidthOutcome in place of a conversation message. On a
#   refusal the channel itself writes Bandwidth's `description` into its external_error
#   (Channel::Sms#handle_error), so the reason is Bandwidth's own text and no HTTP detail of the
#   channel is copied here.
class CampaignJourney::SmsSender
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      @code = code
      super(CampaignImports::SafeLogMessage.call(message))
    end
  end

  NO_ID_REASON = 'SMS provider did not accept the message'.freeze

  def initialize(channel)
    @channel = channel
  end

  def deliver(to:, body:)
    return deliver_twilio(to, body) if @channel.is_a?(Channel::TwilioSms)

    deliver_bandwidth(to, body)
  end

  private

  def deliver_twilio(to, body)
    source_id = @channel.send_message(to: to, body: body)&.sid
    raise Error, NO_ID_REASON if source_id.blank?

    source_id
  rescue Twilio::REST::RestError => e
    raise Error.new(e.error_message.presence || e.message, code: e.code&.to_s)
  rescue Twilio::REST::TwilioError => e
    raise Error, e.message
  end

  def deliver_bandwidth(to, body)
    outcome = CampaignJourney::SmsBandwidthOutcome.new(body)
    source_id = @channel.send_message(to, outcome)
    raise Error, outcome.external_error.presence || NO_ID_REASON if source_id.blank?

    source_id
  end
end
