require 'set'

module WhatsappApiCampaigns
  class AudienceResolver
    def initialize(campaign)
      @campaign = campaign
    end

    def perform
      create_recipients!
      @campaign.refresh_counters!
    end

    private

    def create_recipients!
      seen_phone_hashes = Set.new(@campaign.whatsapp_api_campaign_recipients.where.not(phone_hash: nil).pluck(:phone_hash))
      contacts.find_each(batch_size: 500) do |contact|
        phone_hash = PhonePrivacy.hash(contact.phone_number)
        duplicate_phone = phone_hash.present? && seen_phone_hashes.include?(phone_hash)

        create_recipient_for(contact, phone_hash: phone_hash, duplicate_phone: duplicate_phone)
        # Quem recusou não reserva o número: outro contato com o mesmo telefone ainda recebe.
        seen_phone_hashes << phone_hash if phone_hash.present? && !duplicate_phone && !contact.opted_out?
      end
    end

    def contacts
      label_titles = @campaign.account.labels.where(id: audience_label_ids).pluck(:title)
      return @campaign.account.contacts.none if label_titles.blank?

      @campaign.account.contacts.tagged_with(label_titles, any: true).distinct
    end

    def audience_label_ids
      Array(@campaign.audience).select { |item| item['type'] == 'Label' || item[:type] == 'Label' }.map { |item| item['id'] || item[:id] }.compact
    end

    def create_recipient_for(contact, phone_hash:, duplicate_phone:)
      recipient = @campaign.whatsapp_api_campaign_recipients.find_or_initialize_by(contact: contact)
      return unless recipient.new_record?

      recipient.account = @campaign.account
      recipient.inbox = @campaign.inbox
      recipient.phone_mask = PhonePrivacy.mask(contact.phone_number)
      recipient.phone_hash = phone_hash
      apply_recipient_validation_status(recipient, contact, duplicate_phone)
      recipient.save!
    end

    def apply_recipient_validation_status(recipient, contact, duplicate_phone)
      if contact.opted_out?
        recipient.status = :cancelled
        recipient.last_error_message = WhatsappApiCampaignRecipient::OPTED_OUT_REASON
        recipient.cancelled_at = Time.current
      elsif contact.phone_number.blank?
        recipient.status = :failed
        recipient.last_error_message = 'missing_phone_number'
        recipient.failed_at = Time.current
      elsif duplicate_phone
        recipient.status = :failed
        recipient.last_error_message = 'duplicate_phone_number'
        recipient.failed_at = Time.current
      else
        recipient.status = :pending
      end
    end
  end
end
