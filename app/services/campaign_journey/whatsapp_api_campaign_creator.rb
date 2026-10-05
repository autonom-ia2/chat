# WhatsApp API campaign of the journey (#999, contract in docs/campaigns/publicos/api-999.md):
# the engine's own creator (WhatsappApiCampaigns::Creator: inbox marked for campaigns, saved
# template, free message, optional media, account timezone) plus the audience link, in one
# transaction so the scheduler never sees the campaign without its audience.
#
# `audience` gets a marker entry ({ type: 'CampaignAudience', id: <campaign_import_id> }) only to
# satisfy the model's presence check; who receives comes from the link
# (CampaignJourney::WhatsappApiAudience::Resolver).
#
# Tokens: {{contact.name}}, {{contact.first_name}}, {{contact.company}} and the audience's extra
# columns as {{publico.<key>}} (CampaignJourney::AudienceColumns). variable_defaults gives a text
# per token used when the person has no value (company_default is kept as an alias of
# variable_defaults['contact.company']).
class CampaignJourney::WhatsappApiCampaignCreator < WhatsappApiCampaigns::Creator
  CHANNEL = 'whatsapp_api'.freeze
  MAX_DEFAULT_LENGTH = 1024
  ERROR_CODES = {
    'inbox_not_marked_for_whatsapp_api_campaigns' => 'whatsapp_api_inbox_required',
    'media_file_too_large' => 'media_file_too_large',
    'media_file_type_not_supported' => 'media_file_type_not_supported',
    'template_not_found' => 'template_not_found'
  }.freeze

  def initialize(account:, user:, campaign_import:, params:)
    super(account: account, user: user, params: params)
    @campaign_import = campaign_import
  end

  def perform
    validate_audience!
    ActiveRecord::Base.transaction do
      # Locked and checked again so a concurrent delete or channel switch cannot slip in (#1005).
      @campaign_import.lock!
      validate_audience!
      campaign = super
      CampaignAudienceLink.create!(account: @account, campaign: campaign, campaign_import: @campaign_import,
                                   variable_defaults: variable_defaults(campaign.message_body))
      campaign
    end
  rescue Pundit::NotAuthorizedError
    raise CampaignJourney::CreatorError.new('channel_not_connected', 'WhatsApp API campaigns are not enabled')
  rescue ArgumentError => e
    raise CampaignJourney::CreatorError.new(error_code(e.message), e.message)
  rescue ActiveRecord::RecordInvalid => e
    raise CampaignJourney::CreatorError.new('invalid_campaign', e.record.errors.full_messages.to_sentence)
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound
    raise CampaignJourney::CreatorError.new('audience_not_ready', 'The audience is no longer available')
  end

  private

  def validate_audience!
    unless CampaignJourney::WhatsappCampaignCreator::READY_STATUSES.include?(@campaign_import.status)
      raise CampaignJourney::CreatorError.new('audience_not_ready', 'The audience has not finished saving')
    end
    return if @campaign_import.audience? && CampaignJourney::WhatsappCampaignCreator.whatsapp_available?(@campaign_import)

    raise CampaignJourney::CreatorError.new('channel_not_in_audience', 'This audience has no WhatsApp numbers enabled')
  end

  def error_code(message)
    return 'unsupported_variables' if message.start_with?('unsupported_variables')
    return 'unknown_audience_column' if message.start_with?('unknown_audience_column')

    ERROR_CODES.fetch(message, 'invalid_campaign')
  end

  def column_keys
    @column_keys ||= CampaignJourney::AudienceColumns.key_map(@campaign_import).keys
  end

  # Same check as the engine, plus: a {{publico.<key>}} that is not a column of the audience is
  # refused with unknown_audience_column.
  def selected_body(template)
    body = template&.body.presence || permitted[:message_body].to_s
    unknown_columns = WhatsappApiCampaigns::TemplateRenderer.variables_in(body)
                                                            .filter_map { |token| CampaignJourney::AudienceColumns.column_key(token) } - column_keys
    raise ArgumentError, "unknown_audience_column: #{unknown_columns.join(', ')}" if unknown_columns.any?

    unsupported = WhatsappApiCampaigns::TemplateRenderer.unsupported_variables_in(body, audience_keys: column_keys)
    raise ArgumentError, "unsupported_variables: #{unsupported.join(', ')}" if unsupported.present?

    body
  end

  def campaign_attributes
    super.merge(audience_column_keys: column_keys)
  end

  # Defaults only for tokens the message uses; text squished, up to MAX_DEFAULT_LENGTH.
  def variable_defaults(body)
    texts = permitted[:variable_defaults].to_h.transform_keys(&:to_s)
    texts[WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE] ||= permitted[:company_default]
    texts = texts.transform_values { |text| text.to_s.squish }.compact_blank
    used = WhatsappApiCampaigns::TemplateRenderer.variables_in(body)
    invalid = texts.keys - used
    if invalid.any? || texts.values.any? { |text| text.size > MAX_DEFAULT_LENGTH }
      raise CampaignJourney::CreatorError.new('invalid_variable_defaults', 'Defaults must be short texts for tokens the message uses',
                                              { unknown: invalid })
    end

    texts
  end

  def normalized_audience
    [{ type: 'CampaignAudience', id: @campaign_import.id }]
  end

  # Unknown inbox → the same refusal as an inbox not marked for campaigns (no 404 for a body field).
  def fetch_inbox
    inbox = @account.inboxes.find_by(id: permitted[:inbox_id])
    return inbox if inbox&.api? && inbox.channel.whatsapp_api_campaign_channel?

    raise ArgumentError, 'inbox_not_marked_for_whatsapp_api_campaigns'
  end

  # A saved template of another inbox (or deleted) is a refusal, not a 404.
  def fetch_template(inbox)
    template_id = permitted[:template_id].presence
    return if template_id.blank?

    template = @account.whatsapp_api_message_templates.active.for_inbox(inbox.id).find_by(id: template_id)
    template || raise(ArgumentError, 'template_not_found')
  end

  # The journey sends `scheduled_at: null` for "now".
  def scheduled_at
    permitted[:scheduled_at].present? ? super : Time.current
  end

  def permitted
    @permitted ||= @params.permit(:title, :inbox_id, :template_id, :message_body, :scheduled_at, :company_default, variable_defaults: {})
  end
end
