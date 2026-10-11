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
        previous_primary_id = @card.conversation_id
        card = locked_link
        # Card antigo pode ter a principal sem linha de vínculo: quando outra vira principal, ela sai do card.
        sync_access!(card.conversation_id == previous_primary_id ? nil : previous_primary_id)
        card
      end

      def locked_link
        @card.with_lock do
          validate_contact_compatibility!
          primary = @requested_primary || @card.conversation_id.blank?
          novo = false
          link = Crm::CardConversation.find_or_create_by!(
            account: @card.account,
            card: @card,
            conversation: @conversation
          ) do |record|
            record.linked_by = @actor
            novo = true
          end
          # Vincular é tratar deste pedido nesta conversa (#1147): ele vira o assunto atual, e a IA e o follow-up
          # passam a valer para ele ali. Vínculo que já existia não rouba o foco de ninguém.
          Crm::Cards::Focus.new(account: @card.account, card: @card, conversation: @conversation, user: @actor).perform if novo

          update_card_from_conversation! if primary
          link.update!(is_primary: true) if primary && !link.is_primary?
          log_activity('conversation_linked')
          @card.reload
        end
      end

      def unlink
        card = @card.with_lock do
          Crm::CardConversation.where(card: @card, conversation: @conversation).destroy_all
          if @card.conversation_id == @conversation.id
            @card.update!(conversation_id: nil, last_activity_at: Time.current)
          else
            @card.update!(last_activity_at: Time.current)
          end
          log_activity('conversation_unlinked')
          @card.reload
        end
        sync_access!
        card
      end

      private

      # Acesso por funil (#1148, parte C): o reload dentro da trava zera saved_changes e o after_commit do card não vê
      # a troca de conversa. A conversa vinculada ou desvinculada (e a principal que saiu do card) é sincronizada aqui,
      # depois da trava; a que o aviso do vínculo já pôs na fila não entra de novo.
      def sync_access!(previous_primary_id = nil)
        Crm::Access::CountInvalidation.card_changed!(@card.account_id, [@conversation.id, previous_primary_id])
      end

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
          owner_id: @card.owner_id || derived_owner_id,
          team_id: @card.team_id || @conversation.team_id,
          source: @card.source.presence || @conversation.inbox&.channel_type,
          last_message_at: Crm::Conversations::LastRealMessageAt.for(@conversation),
          last_activity_at: Time.current
        )
      end

      # Acesso por funil (#1148, decisão a): o atendente só vira dono do card sem dono se tiver o funil dele (ou se quem
      # vincula é administrador); senão o card segue sem dono.
      def derived_owner_id
        assignee_id = @conversation.assignee_id
        guard = Crm::Access::CardGuard.new(user: @actor, account: @card.account)
        allowed = guard.owner_allowed?(assignee_id, inbox_id: @card.inbox_id || @conversation.inbox_id, pipeline_id: @card.pipeline_id)
        allowed ? assignee_id : nil
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
