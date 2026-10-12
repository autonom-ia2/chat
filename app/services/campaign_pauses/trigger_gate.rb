# A Chatwoot campaign with an open pause does not fire (#1329). Prepended into Campaign by
# config/initializers/campaign_pauses.rb, so campaign.rb is not edited. The check runs before
# Campaign#trigger! flips the campaign to `processing`: a paused campaign stays `active` and the
# scheduler's next pick is a no-op until someone resumes it (CampaignPauses::Resumer).
module CampaignPauses::TriggerGate
  def trigger!
    return if one_off? && CampaignPause.open_for(self)

    super
  end
end
