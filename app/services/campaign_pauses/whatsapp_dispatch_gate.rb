# Template check before a WhatsApp Oficial campaign goes out (#1329, épico #1320). Prepended into
# Whatsapp::OneoffCampaignService by config/initializers/campaign_pauses.rb, after the campaign
# journey modules, so it is the outermost `perform` and runs before any recipient is created:
#   CampaignPauses::WhatsappDispatchGate → CampaignJourney::WhatsappOneoffRecipients →
#   CampaignJourney::AudienceContacts → Enterprise::Whatsapp::OneoffCampaignService → Chatwoot
# When the template no longer matches (Whatsapp::Templates::DispatchCheck) nobody receives anything:
# the campaign gets an open CampaignPause with the reason and goes back to `active`. Otherwise `super`
# runs untouched — opt-out (chat#737), phone or BSUID destination and the authentication guard
# (Whatsapp::AuthenticationTemplateGuard) stay where they are.
# Every WhatsApp Cloud one-off campaign with template_params goes through the check. A check that
# breaks never sends blind and never leaves the campaign stuck in `processing`: it pauses by the system.
module CampaignPauses::WhatsappDispatchGate
  def perform
    return super unless template_check_applies?

    verdict = template_verdict
    return super if verdict.ok?

    Rails.logger.warn "[CampaignPauses] campaign=#{campaign.id} paused reason=#{verdict.reason_code} source=#{verdict.source}"
    CampaignPauses::Pauser.new(campaign, source: verdict.source, reason_code: verdict.reason_code, details: verdict.details).perform
  end

  private

  def template_check_applies?
    campaign.one_off? && !campaign.completed? && campaign.template_params.present? && whatsapp_cloud_channel? &&
      campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def template_verdict
    Whatsapp::Templates::DispatchCheck.new(campaign, channel: channel).call
  rescue StandardError => e
    Rails.logger.error "[CampaignPauses] campaign=#{campaign.id} template check failed: #{e.class.name}"
    Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: 'template_unverifiable', source: 'system',
                                                    details: { error_class: e.class.name })
  end
end
