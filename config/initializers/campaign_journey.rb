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

  # #999: WhatsApp API campaigns linked to an audience resolve its contacts; {{contact.company}}
  # without a company skips the person ("falta empresa") unless the campaign has a default text.
  prepend_once.call(WhatsappApiCampaigns::AudienceResolver, CampaignJourney::WhatsappApiAudience::Resolver)
  prepend_once.call(WhatsappApiCampaigns::DeliveryEngine, CampaignJourney::WhatsappApiAudience::Delivery)
  # #999: an e-mail campaign linked to an audience takes no spreadsheet of recipients.
  prepend_once.call(Api::V1::Accounts::EmailCampaigns::RecipientsController, CampaignJourney::EmailRecipientsGuard)
  # #999: an e-mail campaign linked to an audience is sendable only while the audience e-mail channel is on.
  prepend_once.call(EmailCampaign, CampaignJourney::EmailAudienceGate::Campaign)
  prepend_once.call(EmailCampaigns::Presentation::SendReadiness, CampaignJourney::EmailAudienceGate::Readiness)
  # #999 review M2: a due linked e-mail campaign syncs its list before the hygiene/admission checks.
  prepend_once.call(EmailCampaigns::Scheduler, CampaignJourney::EmailAudienceGate::Scheduler)

  # #1002: a reply to a campaign marks the conversation in the CRM (listener on message_created).
  # Independent of initializer order: the prepend covers a later load_listeners, ensure_subscribed!
  # a dispatcher that already loaded them. Never subscribed twice.
  prepend_once.call(AsyncDispatcher, CampaignJourney::AsyncDispatcherListeners)
  CampaignJourney::AsyncDispatcherListeners.ensure_subscribed!
end

Rails.application.config.after_initialize do
  CampaignJourney::AsyncDispatcherListeners.ensure_subscribed!
end
