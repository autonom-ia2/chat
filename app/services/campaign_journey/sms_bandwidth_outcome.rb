# What Channel::Sms#send_message reads from a message (outgoing_content, attachments) and writes on
# a refusal (external_error, status, save!), for a journey SMS that is not a conversation message
# (#1004, CampaignJourney::SmsSender). The channel writes Bandwidth's `description` into
# #external_error, so the reason is Bandwidth's own text. Nothing is persisted.
class CampaignJourney::SmsBandwidthOutcome
  attr_reader :outgoing_content
  attr_accessor :external_error, :status

  def initialize(body)
    @outgoing_content = body
  end

  def attachments
    []
  end

  def save!
    true
  end
end
