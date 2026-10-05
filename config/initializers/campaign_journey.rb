# frozen_string_literal: true

# Campaign journey (epic #990) extends Chatwoot campaign behaviour without editing
# upstream files: each extension is a fork module prepended here.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Api::V1::Accounts::CampaignsController, CampaignJourney::WhatsappCloudGuard)

  # #1005: a campaign linked to an audience sends to the audience's contacts (not labels),
  # with queued recipients, per-person variables and a final status for everyone.
  # Prepended after Enterprise::Whatsapp::OneoffCampaignService, so `super` reaches it.
  prepend_once.call(Whatsapp::OneoffCampaignService, CampaignJourney::AudienceContacts)
  prepend_once.call(Whatsapp::OneoffCampaignService, CampaignJourney::WhatsappOneoffRecipients) if ChatwootApp.enterprise?
end
