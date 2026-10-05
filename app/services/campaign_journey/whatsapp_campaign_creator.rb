# Creates a WhatsApp Oficial campaign of the journey (#1005, contract in
# docs/campaigns/publicos/api-1005.md): a normal Chatwoot Campaign (model validations, Cloud
# inbox as in CampaignJourney::WhatsappCloudGuard) plus its CampaignAudienceLink with the
# message variables. Campaign and link are written in one transaction, with the audience row
# locked and checked again inside it, so the scheduler never sees the campaign without its
# audience and a concurrent delete or channel switch cannot slip in between.
class CampaignJourney::WhatsappCampaignCreator
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = nil)
      @code = code
      @details = details
      super(message)
    end
  end

  CHANNEL = 'whatsapp_cloud'.freeze
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

  def self.whatsapp_available?(campaign_import)
    return campaign_import.imported_contacts_count.positive? unless campaign_import.audience?

    CampaignJourney::AudienceContacts.whatsapp_enabled?(campaign_import) && campaign_import.channels.to_h.dig('whatsapp', 'count').to_i.positive?
  end

  private

  def validate_request!
    validate_inbox!
    validate_feature!
    validate_schedule!
    validate_audience!
    validate_variables!
  end

  def create_campaign_and_link!
    campaign = @account.campaigns.create!(campaign_attributes)
    CampaignAudienceLink.create!(
      account: @account, campaign: campaign, campaign_import: @campaign_import,
      variable_bindings: variables.bindings, variable_defaults: variables.defaults
    )
    campaign
  end

  def inbox
    @inbox ||= @account.inboxes.find_by(id: @attributes[:inbox_id])
  end

  def validate_inbox!
    cloud = @channel == CHANNEL && inbox&.inbox_type == 'Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
    raise Error.new('whatsapp_cloud_required', 'WhatsApp campaigns need a WhatsApp Cloud inbox') unless cloud
  end

  def validate_feature!
    return if @account.feature_enabled?(:whatsapp_campaign)

    raise Error.new('feature_disabled', 'WhatsApp campaigns are not enabled for this account')
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
    # #1006: a contact import is not a list for campaigns.
    raise Error.new('not_an_audience', 'A contact import is not an audience') if @campaign_import.contact_import?
    raise Error.new('audience_not_ready', 'The audience has not finished saving') unless READY_STATUSES.include?(@campaign_import.status)
    return if self.class.whatsapp_available?(@campaign_import)

    raise Error.new('channel_not_in_audience', 'This audience has no WhatsApp numbers enabled')
  end

  def validate_variables!
    raise Error.new('template_not_found', 'The template is not approved in this inbox') unless template

    variables.validate!(@campaign_import, template_keys: CampaignJourney::TemplatePlaceholders.keys(template_body))
  rescue CampaignJourney::VariableBindings::Error => e
    raise Error.new(e.message, 'The message variables do not match the template or the audience', e.details.presence)
  end

  def variables
    @variables ||= CampaignJourney::VariableBindings.new(@attributes[:variable_bindings], @attributes[:variable_defaults])
  end

  def campaign_attributes
    {
      title: @attributes[:title], inbox: inbox, scheduled_at: @scheduled_at,
      template_params: @attributes[:template_params], message: @attributes[:message].presence || template_body.presence || template['name'],
      audience: []
    }
  end

  # The approved template the campaign names (same lookup as Whatsapp::TemplateProcessorService).
  def template
    return @template if defined?(@template)

    params = @attributes[:template_params].to_h
    @template = Array(inbox.channel.message_templates).find do |candidate|
      candidate['name'] == params['name'] && candidate['language'].to_s.casecmp?(params['language'].to_s) &&
        candidate['status'].to_s.casecmp?('approved')
    end
  end

  def template_body
    Array(template&.dig('components')).find { |component| component['type'] == 'BODY' }&.dig('text').to_s
  end
end
