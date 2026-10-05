# Públicos (#1005, PRD §8.6, acceptance N2/N3): a campaign linked to an audience sends to the
# audience's contacts (campaign_import_rows.contact_id of imported rows), not to labels.
# Prepended into Whatsapp::OneoffCampaignService by config/initializers/campaign_journey.rb;
# a campaign without a link keeps Chatwoot's label audience untouched.
module CampaignJourney::AudienceContacts
  # WhatsApp needs a phone number. Contacts that refused active messages (#737) are not
  # eligible: they stay out of the total instead of becoming recipients (PRD B8).
  CHANNEL_FILTERS = {
    whatsapp: ->(contacts) { contacts.where.not(phone_number: [nil, '']) }
  }.freeze

  def self.contacts_for(link, channel:)
    return Contact.none if link&.campaign_import.blank?

    contact_ids = link.campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).select(:contact_id)
    contacts = link.campaign_import.account.contacts.where(id: contact_ids).not_opted_out
    CHANNEL_FILTERS.fetch(channel).call(contacts)
  end

  private

  def audience_link
    return @audience_link if defined?(@audience_link)

    @audience_link = CampaignAudienceLink.for_campaign(campaign)
  end

  def audience_contacts
    CampaignJourney::AudienceContacts.contacts_for(audience_link, channel: :whatsapp)
  end

  # Enterprise path (Enterprise::Whatsapp::OneoffCampaignService#perform): recipients first.
  def create_recipients(audience_labels)
    return super unless audience_link

    register_queued_recipients(audience_contacts)
  end

  # OSS path (no recipient tracking): same audience, Chatwoot's per-contact sending.
  def process_audience(audience_labels)
    return super unless audience_link

    Rails.logger.info "Processing audience #{audience_link.campaign_import_id} for campaign #{campaign.id}"
    audience_contacts.find_each { |contact| process_contact(contact) }
  end
end
