# Finds the campaign of a result page (#1007) inside the account and wraps it in its result.
# Channels are the journey's (campaignChannels.js). Chatwoot campaigns are addressed by display_id,
# like every other campaign screen; e-mail and WhatsApp API by id. A campaign of another channel or
# account is not found (404), never shown under the wrong result.
class CampaignJourney::ResultFinder
  EMAIL = 'email'.freeze
  WHATSAPP_OFFICIAL = 'whatsapp_official'.freeze
  WHATSAPP_API = 'whatsapp_api'.freeze
  SMS = 'sms'.freeze
  CHANNELS = [EMAIL, WHATSAPP_OFFICIAL, WHATSAPP_API, SMS].freeze

  def self.channel_of(campaign)
    return unless campaign.one_off?

    inbox = campaign.inbox
    return WHATSAPP_OFFICIAL if inbox.inbox_type == 'Whatsapp'
    return SMS if inbox.channel_type == 'Channel::Sms' || (inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.medium == 'sms')

    nil
  end

  # The audience (Público) the campaign was sent to, when it came from the journey.
  def self.audience_of(campaign)
    audience = CampaignAudienceLink.for_campaign(campaign)&.campaign_import
    audience && { id: audience.id, name: audience.name.presence || audience.campaign_name }
  end

  def initialize(account)
    @account = account
  end

  def find!(channel, id)
    case channel
    when EMAIL then CampaignJourney::EmailResult.new(EmailCampaign.where(account_id: @account.id).find(id), account: @account)
    when WHATSAPP_API then CampaignJourney::WhatsappApiResult.new(WhatsappApiCampaign.where(account_id: @account.id).find(id), account: @account)
    when WHATSAPP_OFFICIAL, SMS then chatwoot_result(channel, id)
    else raise ActiveRecord::RecordNotFound
    end
  end

  private

  def chatwoot_result(channel, id)
    campaign = @account.campaigns.includes(:inbox).find_by!(display_id: id)
    raise ActiveRecord::RecordNotFound unless self.class.channel_of(campaign) == channel

    klass = channel == SMS ? CampaignJourney::SmsRecipientsResult : CampaignJourney::CampaignRecipientsResult
    klass.new(campaign, account: @account)
  end
end
