# Creates an SMS campaign of the journey (#1004, contract in docs/campaigns/publicos/api-1004.md):
# a normal Chatwoot one-off Campaign on the account's SMS inbox (Bandwidth or Twilio SMS) plus its
# CampaignAudienceLink, whose variable_defaults keep the default text per token. The message uses
# the token grammar of the WhatsApp API journey (CampaignJourney::SmsMessage).
class CampaignJourney::SmsCampaignCreator < CampaignJourney::AudienceCampaignCreator
  CHANNEL = 'sms'.freeze

  private

  def link_attributes
    { variable_bindings: {}, variable_defaults: message.defaults }
  end

  # The audience needs its SMS badge on with phones (old imports: any imported contact).
  def audience_available?
    return @campaign_import.imported_contacts_count.positive? unless @campaign_import.audience?

    CampaignJourney::AudienceContacts.sms_enabled?(@campaign_import) && @campaign_import.channels.to_h.dig('sms', 'count').to_i.positive?
  end

  def channel_missing_message
    'This audience has SMS turned off or no phone numbers'
  end

  def validate_inbox!
    return if @channel == CHANNEL && CampaignJourney::CampaignMarks.sms_inbox?(inbox)

    raise Error.new('sms_inbox_required', 'SMS campaigns need an SMS inbox (Twilio SMS or Bandwidth)')
  end

  def validate_message!
    message.validate!
  rescue CampaignJourney::SmsMessage::Error => e
    raise Error.new(e.message, 'The message tokens do not match the audience', e.details.presence)
  end

  def message
    @message ||= CampaignJourney::SmsMessage.new(
      @attributes[:message], campaign_import: @campaign_import, defaults: @attributes[:variable_defaults]
    )
  end

  def campaign_attributes
    { title: @attributes[:title], inbox: inbox, scheduled_at: @scheduled_at, message: @attributes[:message], audience: [] }
  end
end
