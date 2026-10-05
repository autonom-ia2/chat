# Creates a WhatsApp Oficial campaign of the journey (#1005, contract in
# docs/campaigns/publicos/api-1005.md): a normal Chatwoot Campaign (model validations, Cloud
# inbox as in CampaignJourney::WhatsappCloudGuard) plus its CampaignAudienceLink with the
# message variables. Transaction, audience lock and shared checks in
# CampaignJourney::AudienceCampaignCreator.
class CampaignJourney::WhatsappCampaignCreator < CampaignJourney::AudienceCampaignCreator
  CHANNEL = 'whatsapp_cloud'.freeze

  def self.whatsapp_available?(campaign_import)
    phone_available?(campaign_import)
  end

  private

  def link_attributes
    { variable_bindings: variables.bindings, variable_defaults: variables.defaults }
  end

  def validate_inbox!
    cloud = @channel == CHANNEL && inbox&.inbox_type == 'Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
    raise Error.new('whatsapp_cloud_required', 'WhatsApp campaigns need a WhatsApp Cloud inbox') unless cloud
  end

  def validate_feature!
    return if @account.feature_enabled?(:whatsapp_campaign)

    raise Error.new('feature_disabled', 'WhatsApp campaigns are not enabled for this account')
  end

  def channel_missing_message
    'This audience has no WhatsApp numbers enabled'
  end

  def validate_message!
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
