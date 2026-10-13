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

    validate_free_text!

    variables.validate!(@campaign_import, template_keys: CampaignJourney::TemplateVariableKeys.keys(template))
    template_params
  rescue CampaignJourney::VariableBindings::Error => e
    raise Error.new(e.message, 'The message variables do not match the template or the audience', e.details.presence)
  rescue Whatsapp::Templates::HeaderMedia::Invalid => e
    raise Error.new(e.code, 'The template needs what Meta asks at send time (header or card file, coupon code, offer expiration)')
  end

  # #1335: a mensagem escrita para quem falou com a caixa nas últimas 24 h, conferida antes de gravar (flag da conta).
  def validate_free_text!
    return if free_text.blank?
    raise Error.new('free_text_disabled', 'Free text is not enabled for this account') unless CampaignJourney::ConversaAberta.enabled?(@account)
    # Código de acesso (AUTHENTICATION) nunca vai como texto livre.
    raise Error.new('free_text_invalid', 'The free text cannot be sent', { reason: 'authentication_template' }) if authentication_template?
    # #1456: cupom, oferta com prazo ou carrossel só no modelo completo (quem recebesse o texto perderia a oferta).
    if Whatsapp::Templates::SendableFormat.offer_format?(template)
      raise Error.new('free_text_not_allowed_with_rich_template', 'Templates with a coupon, a limited-time offer or a carousel go to everyone')
    end

    permitidas = CampaignJourney::ConversaAberta::Texto.chaves_permitidas(@campaign_import.extra_columns)
    reason = CampaignJourney::ConversaAberta::Texto.problema(free_text, permitidas: permitidas)
    raise Error.new('free_text_invalid', 'The free text cannot be sent', { reason: reason.to_s }) if reason
  end

  def create_campaign_and_link!
    campaign = super
    CampaignFreeText.create!(account: @account, campaign: campaign, content: free_text) if free_text.present?
    campaign
  end

  def free_text
    @attributes[:free_text].to_s.strip
  end

  def authentication_template?
    template.to_h['category'].to_s.casecmp?('AUTHENTICATION')
  end

  # #1382: a media header without a link uses the template's saved file at send time; a typed link is checked here.
  # #1334: coupon, offer expiration, carousel cards and catalog button (Whatsapp::Templates::SendParams).
  def template_params
    @template_params ||= begin
      params = @attributes[:template_params].to_h.deep_stringify_keys
      processed = params['processed_params']
      processed.is_a?(Hash) ? params.merge('processed_params' => normalized_processed(processed)) : params
    end
  end

  def normalized_processed(processed)
    if Whatsapp::Templates::HeaderMedia.media_type(template)
      processed = processed.merge('header' => Whatsapp::Templates::HeaderMedia.normalize!(processed['header'], template: template, inbox: inbox))
    end
    Whatsapp::Templates::SendParams.normalize!(processed, template: template, inbox: inbox)
  end

  def variables
    @variables ||= CampaignJourney::VariableBindings.new(@attributes[:variable_bindings], @attributes[:variable_defaults])
  end

  def campaign_attributes
    {
      title: @attributes[:title], inbox: inbox, scheduled_at: @scheduled_at,
      template_params: template_params, message: @attributes[:message].presence || template_body.presence || template['name'],
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
