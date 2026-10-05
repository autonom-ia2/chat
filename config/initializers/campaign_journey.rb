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

  # #1004: an SMS campaign linked to an audience sends to the audience's phones with a recipient
  # per person; delivery callbacks of Twilio and Bandwidth update those recipients.
  prepend_once.call(Sms::OneoffSmsCampaignService, CampaignJourney::SmsOneoffRecipients)
  prepend_once.call(Twilio::OneoffSmsCampaignService, CampaignJourney::SmsOneoffRecipients)
  prepend_once.call(Twilio::DeliveryStatusService, CampaignJourney::SmsDeliveryStatus::TwilioCallback)
  prepend_once.call(Webhooks::SmsEventsJob, CampaignJourney::SmsDeliveryStatus::BandwidthCallback)

  # #1002: a reply to a campaign marks the conversation in the CRM (listener on message_created).
  # Independent of initializer order: the prepend covers a later load_listeners, ensure_subscribed!
  # a dispatcher that already loaded them. Never subscribed twice.
  prepend_once.call(AsyncDispatcher, CampaignJourney::AsyncDispatcherListeners)
  CampaignJourney::AsyncDispatcherListeners.ensure_subscribed!
end

Rails.application.config.after_initialize do
  CampaignJourney::AsyncDispatcherListeners.ensure_subscribed!
end
