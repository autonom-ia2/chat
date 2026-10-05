# Sends one SMS of a journey campaign through the inbox's own channel method (#1004) and returns
# the provider's message id, or raises Error with a readable reason (D4).
#
# - Twilio SMS: Channel::TwilioSms#send_message (it already asks Twilio for the StatusCallback);
#   the id is the message SID. A refusal keeps Twilio's code and message.
# - Bandwidth (Channel::Sms): Channel::Sms#send_text_message returns the message id or nil; on nil
#   the channel only logs Bandwidth's description, so the reason here is generic. The real
#   reason of an accepted message that fails later arrives by the delivery callback.
class CampaignJourney::SmsSender
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      @code = code
      super(message)
    end
  end

  NO_ID_REASON = 'SMS provider did not accept the message'.freeze

  def initialize(channel)
    @channel = channel
  end

  def deliver(to:, body:)
    source_id = @channel.is_a?(Channel::TwilioSms) ? deliver_twilio(to, body) : @channel.send_text_message(to, body)
    raise Error, NO_ID_REASON if source_id.blank?

    source_id
  end

  private

  def deliver_twilio(to, body)
    @channel.send_message(to: to, body: body)&.sid
  rescue Twilio::REST::RestError => e
    raise Error.new(e.error_message.presence || e.message, code: e.code&.to_s)
  rescue Twilio::REST::TwilioError => e
    raise Error, e.message
  end
end
