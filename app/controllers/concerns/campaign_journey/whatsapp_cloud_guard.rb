# WhatsApp one-off campaigns are only delivered through the WhatsApp Cloud provider
# (Whatsapp::OneoffCampaignService#validate_provider!). Refusing other WhatsApp inboxes
# when the campaign is saved through the API stops a campaign from getting stuck in
# "processing" at send time with no recipients recorded. The check lives on the API path
# (not on the model) so upstream behaviour and specs stay untouched.
# Prepended by config/initializers/campaign_journey.rb.
module CampaignJourney::WhatsappCloudGuard
  def create
    return render_whatsapp_cloud_required if campaign_journey_non_cloud_whatsapp?

    super
  end

  def update
    return render_whatsapp_cloud_required if campaign_params[:inbox_id].present? && campaign_journey_non_cloud_whatsapp?

    super
  end

  private

  def campaign_journey_non_cloud_whatsapp?
    inbox = Current.account.inboxes.find_by(id: campaign_params[:inbox_id])
    return false unless inbox&.inbox_type == 'Whatsapp'

    inbox.channel.provider != 'whatsapp_cloud'
  end

  def render_whatsapp_cloud_required
    render json: { error: 'WhatsApp campaigns need a WhatsApp Cloud inbox', code: 'whatsapp_cloud_required' },
           status: :unprocessable_entity
  end
end
