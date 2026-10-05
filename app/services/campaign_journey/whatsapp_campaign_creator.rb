# Creates a WhatsApp Oficial campaign of the journey (#1005, contract in
# docs/campaigns/publicos/api-1005.md): a normal Chatwoot Campaign (model validations, Cloud
# inbox as in CampaignJourney::WhatsappCloudGuard) plus its CampaignAudienceLink with the
# message variables. Campaign and link are written in one transaction, so the scheduler never
# sees the campaign without its audience.
class CampaignJourney::WhatsappCampaignCreator
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  CHANNEL = 'whatsapp_cloud'.freeze
  READY_STATUSES = %w[completed completed_with_failures].freeze

  def initialize(account:, campaign_import:, channel:, attributes:)
    @account = account
    @campaign_import = campaign_import
    @channel = channel.to_s
    @attributes = attributes.to_h.with_indifferent_access
  end

  def perform
    validate_inbox!
    validate_audience!
    validate_variables!
    ActiveRecord::Base.transaction do
      campaign = @account.campaigns.create!(campaign_attributes)
      CampaignAudienceLink.create!(
        account: @account, campaign: campaign, campaign_import: @campaign_import,
        variable_bindings: variables.bindings, variable_defaults: variables.defaults
      )
      campaign
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error.new('invalid_campaign', e.record.errors.full_messages.to_sentence)
  end

  def self.whatsapp_available?(campaign_import)
    return campaign_import.imported_contacts_count.positive? unless campaign_import.audience?

    whatsapp = campaign_import.channels.to_h['whatsapp'].to_h
    whatsapp['enabled'] == true && whatsapp['count'].to_i.positive?
  end

  private

  def inbox
    @inbox ||= @account.inboxes.find_by(id: @attributes[:inbox_id])
  end

  def validate_inbox!
    cloud = @channel == CHANNEL && inbox&.inbox_type == 'Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
    raise Error.new('whatsapp_cloud_required', 'WhatsApp campaigns need a WhatsApp Cloud inbox') unless cloud
  end

  def validate_audience!
    raise Error.new('audience_not_ready', 'The audience has not finished saving') unless READY_STATUSES.include?(@campaign_import.status)
    return if self.class.whatsapp_available?(@campaign_import)

    raise Error.new('channel_not_in_audience', 'This audience has no WhatsApp numbers enabled')
  end

  def validate_variables!
    variables.validate!(@campaign_import)
  rescue CampaignJourney::VariableBindings::Error => e
    raise Error.new(e.message, 'The message variables do not match the audience')
  end

  def variables
    @variables ||= CampaignJourney::VariableBindings.new(@attributes[:variable_bindings], @attributes[:variable_defaults])
  end

  def campaign_attributes
    {
      title: @attributes[:title], inbox: inbox, scheduled_at: @attributes[:scheduled_at].presence,
      template_params: @attributes[:template_params], message: message, audience: []
    }
  end

  # The template body (with its {{N}} placeholders) unless the screen sent the message text.
  def message
    @attributes[:message].presence || template_body.presence || @attributes.dig(:template_params, :name)
  end

  def template_body
    params = @attributes[:template_params].to_h
    template = Array(inbox.channel.message_templates).find do |candidate|
      candidate['name'] == params['name'] && candidate['language'].to_s.casecmp?(params['language'].to_s)
    end
    Array(template&.dig('components')).find { |component| component['type'] == 'BODY' }&.dig('text')
  end
end
