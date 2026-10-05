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
#
# E-mail (#999) follows the same rule: only rows that HAD a valid e-mail (normalized_email_hash)
# whose contact still has that address (case-insensitive). A row with only a phone never receives
# e-mail, even if the contact has an e-mail on file. One recipient per address (first row wins).
module CampaignJourney::AudienceContacts
  BATCH_SIZE = 1000
  CHANNELS = %i[whatsapp email].freeze
  EmailMatch = Struct.new(:contact_id, :email, :row, keyword_init: true)
  CHANNEL_DISABLED_REASON = 'Canal WhatsApp desligado no público'.freeze

  class << self
    def contacts_for(link, channel:)
      raise ArgumentError, "unsupported channel #{channel}" unless CHANNELS.include?(channel)
      return Contact.none if link&.campaign_import.blank?

      account = link.campaign.account
      ids = if channel == :whatsapp
              whatsapp_contact_ids(link.campaign_import, account: account)
            else
              email_matches(link.campaign_import, account: account).map(&:contact_id)
            end
      account.contacts.where(id: ids).not_opted_out
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

    # Rows that had a valid e-mail that their contact still has, one per address (the first row wins).
    def email_matches(campaign_import, account:)
      return [] if campaign_import.blank? || campaign_import.account_id != account.id

      seen = Set.new
      matches = []
      email_rows(campaign_import).in_batches(of: BATCH_SIZE) do |batch|
        rows = batch.to_a
        emails = account.contacts.where(id: rows.map(&:contact_id)).pluck(:id, :email).to_h
        rows.each do |row|
          email = normalized_email(emails[row.contact_id])
          next unless email && Digest::SHA256.hexdigest(email) == row.normalized_email_hash && seen.add?(email)

          matches << EmailMatch.new(contact_id: row.contact_id, email: email, row: row)
        end
      end
      matches
    end

    # channels of a saved audience with the WhatsApp and e-mail counts recomputed by the rules
    # above; a channel left without contacts is turned off (it cannot be turned on again, J6).
    def recounted_channels(campaign_import)
      account = campaign_import.account
      counts = { 'whatsapp' => whatsapp_contact_ids(campaign_import, account: account).size,
                 'email' => email_matches(campaign_import, account: account).size }
      channels = campaign_import.channels.to_h
      counts.reduce(channels) do |result, (name, count)|
        channel = channels[name].to_h
        result.merge(name => channel.merge('count' => count, 'enabled' => channel['enabled'] == true && count.positive?))
      end
    end

    # Old imports (Base Campanha) have no channel switch; audiences need WhatsApp on.
    def whatsapp_enabled?(campaign_import)
      return false if campaign_import.blank?
      return true unless campaign_import.audience?

      campaign_import.channels.to_h.dig('whatsapp', 'enabled') == true
    end

    # E-mail only exists for audiences, and needs the channel on (fails closed).
    def email_enabled?(campaign_import)
      campaign_import.present? && campaign_import.audience? && campaign_import.channels.to_h.dig('email', 'enabled') == true
    end

    private

    def phone_rows(campaign_import)
      campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).where.not(normalized_phone_hash: nil)
    end

    def email_rows(campaign_import)
      campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).where.not(normalized_email_hash: nil)
    end

    def normalized_email(address)
      EmailCampaigns::EmailNormalizer.normalize!(address).email
    rescue EmailCampaigns::EmailNormalizer::Error
      nil
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
