# Creates a Chatwoot Campaign of the journey that sends to a saved audience (#1005 WhatsApp
# Oficial, #1004 SMS): a normal Campaign (model validations) plus its CampaignAudienceLink.
# Campaign and link are written in one transaction, with the audience row locked and checked
# again inside it, so the scheduler never sees the campaign without its audience and a concurrent
# delete or channel switch cannot slip in between.
#
# Subclasses give the channel rules: #validate_inbox!, #validate_feature!, #validate_message!,
# #campaign_attributes and #link_attributes, and #audience_available? when the channel has its own
# audience badge (SMS: `channels.sms`; WhatsApp: `channels.whatsapp`).
class CampaignJourney::AudienceCampaignCreator
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = nil)
      @code = code
      @details = details
      super(message)
    end
  end

  READY_STATUSES = %w[completed completed_with_failures].freeze
  # A schedule a little in the past (clock skew, slow form) still counts as "now".
  SCHEDULE_TOLERANCE = 5.minutes

  def initialize(account:, campaign_import:, channel:, attributes:)
    @account = account
    @campaign_import = campaign_import
    @channel = channel.to_s
    @attributes = attributes.to_h.with_indifferent_access
  end

  def perform
    validate_request!
    ActiveRecord::Base.transaction do
      @campaign_import.lock!
      validate_audience!
      create_campaign_and_link!
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error.new('invalid_campaign', e.record.errors.full_messages.to_sentence)
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound
    raise Error.new('audience_not_ready', 'The audience is no longer available')
  end

  # The audience has phones the campaign may use (old imports: any imported contact).
  def self.phone_available?(campaign_import)
    return campaign_import.imported_contacts_count.positive? unless campaign_import.audience?

    CampaignJourney::AudienceContacts.whatsapp_enabled?(campaign_import) && campaign_import.channels.to_h.dig('whatsapp', 'count').to_i.positive?
  end

  private

  def validate_request!
    validate_inbox!
    validate_feature!
    validate_schedule!
    validate_audience!
    validate_message!
  end

  def validate_feature!; end

  def create_campaign_and_link!
    campaign = @account.campaigns.create!(campaign_attributes)
    CampaignAudienceLink.create!(account: @account, campaign: campaign, campaign_import: @campaign_import, **link_attributes)
    campaign
  end

  def inbox
    @inbox ||= @account.inboxes.find_by(id: @attributes[:inbox_id])
  end

  def validate_schedule!
    raw = @attributes[:scheduled_at]
    return if raw.blank?

    @scheduled_at = Time.zone.iso8601(raw.to_s)
    raise ArgumentError if @scheduled_at < SCHEDULE_TOLERANCE.ago
  rescue ArgumentError
    raise Error.new('invalid_schedule', 'The schedule must be a future date and time (ISO 8601)')
  end

  def validate_audience!
    raise Error.new('audience_not_ready', 'The audience has not finished saving') unless READY_STATUSES.include?(@campaign_import.status)
    return if audience_available?

    raise Error.new('channel_not_in_audience', channel_missing_message)
  end

  def audience_available?
    self.class.phone_available?(@campaign_import)
  end

  def channel_missing_message
    'This audience has no phone numbers enabled'
  end
end
