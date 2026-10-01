module Crm
  module Cards
    class ConversationLinker
      def initialize(card:, conversation:, actor:, primary: false)
        @card = card
        @conversation = conversation
        @actor = actor
        @requested_primary = primary
      end

      def link
        @card.with_lock do
          validate_contact_compatibility!
          primary = @requested_primary || @card.conversation_id.blank?
          link = Crm::CardConversation.find_or_create_by!(
            account: @card.account,
            card: @card,
            conversation: @conversation
          ) do |record|
            record.linked_by = @actor
          end

          update_card_from_conversation! if primary
          link.update!(is_primary: true) if primary && !link.is_primary?
          log_activity('conversation_linked')
          @card.reload
        end
      end

      def unlink
        @card.with_lock do
          Crm::CardConversation.where(card: @card, conversation: @conversation).destroy_all
          if @card.conversation_id == @conversation.id
            @card.update!(conversation_id: nil, last_activity_at: Time.current)
          else
            @card.update!(last_activity_at: Time.current)
          end
          log_activity('conversation_unlinked')
          @card.reload
        end
      end

      private

      # This entry point is independent of ContactLinker: checking only a contact
      # swap still allowed the reverse operation to attach somebody else's chat.
      def validate_contact_compatibility!
        contact_id = @conversation.contact_id
        current_ids = [@card.contact_id, @card.primary_conversation&.contact_id].compact
        conflict = current_ids.any? { |id| id != contact_id } || @card.linked_conversations.where.not(contact_id: contact_id).exists?
        return unless conflict

        @card.errors.add(:contact, I18n.t('errors.crm.contact_conversation_conflict'))
        raise ActiveRecord::RecordInvalid, @card
      end

      def update_card_from_conversation!
        @card.update!(
          conversation_id: @conversation.id,
          contact_id: @card.contact_id || @conversation.contact_id,
          inbox_id: @card.inbox_id || @conversation.inbox_id,
          owner_id: @card.owner_id || @conversation.assignee_id,
          team_id: @card.team_id || @conversation.team_id,
          source: @card.source.presence || @conversation.inbox&.channel_type,
          last_message_at: Crm::Conversations::LastRealMessageAt.for(@conversation),
          last_activity_at: Time.current
        )
      end

      def log_activity(event_type)
        Crm::ActivityLogger.new(
          card: @card,
          actor: @actor,
          event_type: event_type,
          conversation: @conversation,
          payload: { conversation_id: @conversation.id }
        ).perform
      end
    end
  end
end
