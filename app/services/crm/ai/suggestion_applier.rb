module Crm
  module Ai
    class SuggestionApplier
      def initialize(card:, suggestion:, actor:, auto: false)
        @card = card
        @suggestion = suggestion
        @actor = actor
        @auto = auto
      end

      def perform
        return fechar if @suggestion.fechar
        return @card if @suggestion.to_stage_id == @card.stage_id

        moved_card = Crm::Cards::Mover.new(
          card: @card,
          actor: @actor,
          target_stage: @suggestion.to_stage,
          automation_context: { source: 'crm_ai', suggestion_id: @suggestion.id }
        ).perform

        update_suggestion_status!
        update_auto_move_metadata! if @auto
        broadcast_card(moved_card)
        moved_card
      end

      private

      # IA entende a conversa F3: a sugestão de fechar aceita fecha o card (Crm::Ai::FecharCard.aceitar!) com a pessoa
      # como autora; nunca é automática (a IA que fecha sozinha não passa por aqui).
      def fechar
        @suggestion.fechar_desligado? ? @suggestion.update!(status: :expired) : Crm::Ai::FecharCard.aceitar!(@suggestion, ator: @actor)
        @card.reload
      end

      def update_suggestion_status!
        @suggestion.update!(status: @auto ? :auto_applied : :accepted)
      end

      def update_auto_move_metadata!
        metadata = (@card.metadata || {}).deep_dup
        ai_meta = (metadata['ai'] || {}).dup
        ai_meta['last_auto_move_at'] = Time.current.iso8601
        metadata['ai'] = ai_meta
        @card.update!(metadata: metadata)
      end

      def broadcast_card(card)
        Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED)
      end
    end
  end
end
