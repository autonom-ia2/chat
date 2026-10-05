require 'digest'

# Públicos (#1005, PRD §8.6, acceptance N2/N3): a campaign linked to an audience sends to the
# audience's contacts, not to labels. Prepended into Whatsapp::OneoffCampaignService by
# config/initializers/campaign_journey.rb; a campaign without a link keeps Chatwoot's label
# audience untouched.
#
# Who may receive WhatsApp (consent, review A1): only contacts of imported rows that HAD a valid
# mobile in the spreadsheet (normalized_phone_hash) and whose stored phone is still that mobile
# (same number, with or without the 9th digit). A row with only an email never receives
# WhatsApp. Contacts that refused active messages (#737) stay out of the total (PRD B8).
# The audience's WhatsApp channel must be on at send time; off → nobody, every eligible contact
# is recorded as skipped with CHANNEL_DISABLED_REASON (fails closed).
module CampaignJourney::AudienceContacts
  BATCH_SIZE = 1000
  CHANNEL_DISABLED_REASON = 'Canal WhatsApp desligado no público'.freeze

  # SMS (#1004) goes to the same phone the row brought: the WhatsApp rule above.
  PHONE_CHANNELS = %i[whatsapp sms].freeze

  class << self
    def contacts_for(link, channel:)
      raise ArgumentError, "unsupported channel #{channel}" unless PHONE_CHANNELS.include?(channel)
      return Contact.none if link&.campaign_import.blank?

      account = link.campaign.account
      account.contacts.where(id: whatsapp_contact_ids(link.campaign_import, account: account)).not_opted_out
    end

    # Contact ids whose row had a valid mobile that the contact still has. Same rule for the
    # audience channel count (CampaignImports::Importer) and for who the send reaches.
    def whatsapp_contact_ids(campaign_import, account:)
      return [] if campaign_import.blank? || campaign_import.account_id != account.id

      matcher = CampaignImports::ContactMatcher.new(account)
      ids = []
      phone_rows(campaign_import).in_batches(of: BATCH_SIZE) do |batch|
        pairs = batch.pluck(:contact_id, :normalized_phone_hash)
        phones = account.contacts.where(id: pairs.map(&:first)).pluck(:id, :phone_number).to_h
        pairs.each { |contact_id, hash| ids << contact_id if phone_hashes(matcher, phones[contact_id]).include?(hash) }
      end
      ids.uniq
    end

    # channels of a saved audience with the WhatsApp count recomputed by the rule above; a
    # channel left without contacts is turned off (it cannot be turned on again, J6).
    def recounted_channels(campaign_import)
      channels = campaign_import.channels.to_h
      count = whatsapp_contact_ids(campaign_import, account: campaign_import.account).size
      whatsapp = channels['whatsapp'].to_h
      channels.merge('whatsapp' => whatsapp.merge('count' => count, 'enabled' => whatsapp['enabled'] == true && count.positive?))
    end

    # Old imports (Base Campanha) have no channel switch; audiences need WhatsApp on.
    def whatsapp_enabled?(campaign_import)
      return false if campaign_import.blank?
      return true unless campaign_import.audience?

      campaign_import.channels.to_h.dig('whatsapp', 'enabled') == true
    end

    private

    def phone_rows(campaign_import)
      campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).where.not(normalized_phone_hash: nil)
    end

    def phone_hashes(matcher, phone_number)
      return [] if phone_number.blank?

      matcher.candidates(phone_number).map { |candidate| Digest::SHA256.hexdigest(candidate) }
    end
  end

  private

  def audience_link
    return @audience_link if defined?(@audience_link)

    @audience_link = CampaignAudienceLink.for_campaign(campaign)
  end

  def audience_contacts
    CampaignJourney::AudienceContacts.contacts_for(audience_link, channel: :whatsapp)
  end

  def audience_whatsapp_enabled?
    CampaignJourney::AudienceContacts.whatsapp_enabled?(audience_link.campaign_import)
  end

  # Enterprise path (Enterprise::Whatsapp::OneoffCampaignService#perform): recipients first.
  def create_recipients(audience_labels)
    return super unless audience_link
    return register_queued_recipients(audience_contacts) if audience_whatsapp_enabled?

    skip_all_recipients(audience_contacts, CHANNEL_DISABLED_REASON)
  end

  # OSS path (no recipient tracking): same audience, Chatwoot's per-contact sending.
  def process_audience(audience_labels)
    return super unless audience_link
    return Rails.logger.info("Audience WhatsApp off for campaign #{campaign.id}") unless audience_whatsapp_enabled?

    audience_contacts.find_each { |contact| process_contact(contact) }
  end
end
