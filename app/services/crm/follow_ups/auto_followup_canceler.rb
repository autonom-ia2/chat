module Crm
  module FollowUps
    # Primary auto-stop path for the AI follow-up cadence: when the contact
    # REPLIES (inbound message), cancel every pending ai_followup touch on the
    # card immediately, instead of waiting for the next due sweep. Invoked from
    # Crm::Conversations::CardSyncer on every synced message.
    #
    # Strictly guarded and additive: it does NOTHING unless the triggering
    # message is INBOUND and the card has an ACTIVE ai_followup cadence. Manual
    # follow-ups, stage-automation follow-ups and the sync/AI-evaluation flow are
    # never touched.
    #
    # Qualquer resposta para a cadência — isso não depende de entender o texto. Se a resposta foi um PEDIDO PARA
    # PARAR é o modelo que decide, no OptOutDecisionJob (#1317); até lá o estado fica `opt_out_decision: pendente`.
    class AutoFollowupCanceler
      def initialize(card:, message: nil)
        @card = card
        @message = message
      end

      def maybe_cancel
        return unless @message&.incoming?
        return unless cadence_active?
        # Multifunil (#1606, corrida f): a resposta sobre outro pedido não para a cadência deste card. O mesmo critério
        # do Runner, com a regra única de "qual funil manda" (Crm::Assunto).
        return unless Crm::Assunto.atual?(@card, @message.conversation)

        cancel_pending_follow_ups
        write_state
        log_stopped
        Crm::FollowUps::OptOutDecisionJob.perform_later(@card.id, @message.id)
      end

      private

      def cadence_active?
        state['active'] == true
      end

      def cancel_pending_follow_ups
        @card.follow_ups.active.find_each do |follow_up|
          next unless follow_up.metadata.to_h['source'] == 'ai_followup'

          follow_up.update!(status: :canceled)
        end
      end

      def state
        (@card.metadata || {}).fetch('ai', {}).to_h.fetch('auto_followup_state', {}).to_h
      end

      def write_state
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] ||= {}
        metadata['ai']['auto_followup_state'] = state.merge(
          'active' => false,
          'stopped_reason' => 'replied',
          'opted_out' => false,
          'next_due_at' => nil,
          'stopped_message_id' => @message.id,
          'opt_out_decision' => 'pendente',
          'opt_out_motivo' => nil
        )
        @card.update!(metadata: metadata)
      end

      def log_stopped
        Crm::ActivityLogger.new(
          card: @card,
          actor: nil,
          event_type: 'ai_followup_stopped',
          conversation: @card.primary_conversation,
          payload: { reason: 'replied', trigger: 'inbound_reply', message_id: @message.id }
        ).perform
      end
    end
  end
end
