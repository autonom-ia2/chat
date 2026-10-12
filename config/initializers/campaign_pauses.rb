# frozen_string_literal: true

# Campaign pauses (#1329): why a campaign is paused, in a fork table (CampaignPause). Fork modules
# prepended here, so no Chatwoot file is edited. Loaded after campaign_journey.rb, so the dispatch
# gate is prepended after the journey modules and its `perform` runs first (see
# CampaignPauses::WhatsappDispatchGate for the chain).
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Campaign, CampaignPauses::TriggerGate)
  prepend_once.call(Whatsapp::OneoffCampaignService, CampaignPauses::WhatsappDispatchGate)
end
