module Crm
  module Cards
    class ContactLinker
      def initialize(card:, contact:, actor:)
        @card = card
        @contact = contact
        @actor = actor
      end

      def link
        @card.with_lock do
          next @card if @card.contact_id == @contact.id

          validate_conversation_contacts!
          previous_contact_id = @card.contact_id
          @card.update!(contact: @contact, last_activity_at: Time.current)
          log_activity('contact_linked', previous_contact_id: previous_contact_id)
          @card
        end
      end

      def unlink
        @card.with_lock do
          next @card if @card.contact_id.nil?

          contact_id = @card.contact_id
          @card.update!(contact_id: nil, last_activity_at: Time.current)
          log_activity('contact_unlinked', contact_id: contact_id)
          @card
        end
      end

      private

      # Include legacy primary conversations even when their join row is missing.
      # The card lock refreshes stale associations before checking the persisted links.
      def validate_conversation_contacts!
        primary_contact_id = @card.primary_conversation&.contact_id
        primary_conflict = primary_contact_id.present? && primary_contact_id != @contact.id
        secondary_conflict = @card.linked_conversations.where.not(contact_id: @contact.id).exists?
        return unless primary_conflict || secondary_conflict

        @card.errors.add(:contact, I18n.t('errors.crm.contact_conversation_conflict'))
        raise ActiveRecord::RecordInvalid, @card
      end

      def log_activity(event_type, contact_id: @contact&.id, previous_contact_id: nil)
        Crm::ActivityLogger.new(
          card: @card,
          actor: @actor,
          event_type: event_type,
          payload: { contact_id: contact_id, previous_contact_id: previous_contact_id }.compact
        ).perform
      end
    end
  end
end
