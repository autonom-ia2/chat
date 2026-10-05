# WhatsApp API campaign of the journey (#999, contract in docs/campaigns/publicos/api-999.md):
# the engine's own creator (WhatsappApiCampaigns::Creator: inbox marked for campaigns, saved
# template, free message, optional media, account timezone) plus the audience link, in one
# transaction so the scheduler never sees the campaign without its audience.
#
# `audience` gets a marker entry ({ type: 'CampaignAudience', id: <campaign_import_id> }) only to
# satisfy the model's presence check; who receives comes from the link
# (CampaignJourney::WhatsappApiAudience::Resolver).
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
    defaults = company_default
    ActiveRecord::Base.transaction do
      # Locked and checked again so a concurrent delete or channel switch cannot slip in (#1005).
      @campaign_import.lock!
      validate_audience!
      campaign = super
      CampaignAudienceLink.create!(account: @account, campaign: campaign, campaign_import: @campaign_import,
                                   variable_defaults: defaults)
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

    ERROR_CODES.fetch(message, 'invalid_campaign')
  end

  def company_default
    text = permitted[:company_default].to_s.squish
    return {} if text.blank?
    raise CampaignJourney::CreatorError.new('invalid_campaign', 'The default company text is too long') if text.size > MAX_DEFAULT_LENGTH

    { WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE => text }
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
    @permitted ||= @params.permit(:title, :inbox_id, :template_id, :message_body, :scheduled_at, :company_default)
  end
end
