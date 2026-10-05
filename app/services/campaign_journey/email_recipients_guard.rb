# An e-mail campaign linked to an audience (#999) gets its recipients from the audience only:
# uploading a spreadsheet of recipients to it is refused, so the list is never a mix.
# Prepended into Api::V1::Accounts::EmailCampaigns::RecipientsController by
# config/initializers/campaign_journey.rb (@campaign is loaded by its before_action).
module CampaignJourney::EmailRecipientsGuard
  def create
    return render_audience_linked if CampaignAudienceLink.for_campaign(@campaign)

    super
  end

  def retry_import
    return render_audience_linked if CampaignAudienceLink.for_campaign(@campaign)

    super
  end

  private

  def render_audience_linked
    render json: { error: 'email_campaign.audience_linked' }, status: :unprocessable_entity
  end
end
