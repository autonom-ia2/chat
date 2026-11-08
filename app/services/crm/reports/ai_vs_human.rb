module Crm
  module Reports
    # How much of the stage movement is driven by AI vs humans, derived from the
    # authoritative crm_ai_stage_suggestions.status (never reconstructed from
    # move JSON). Scoped to the period by suggestion created_at.
    #
    #   auto_applied -> AI moved the card automatically
    #   accepted     -> human accepted an AI suggestion
    #   dismissed    -> human rejected an AI suggestion
    #   pending      -> awaiting a human decision
    #   expired      -> suggestion went stale
    #
    # #2000: com `todos_os_funis`, soma os funis que a pessoa enxerga (a frase da Gestão de IA), em vez de um funil só.
    class AiVsHuman < BaseReport
      def perform
        # O group de um enum devolve o nome ("accepted"), não o número: ler pelo número dava zero sempre (#2000).
        counts = suggestions.group(:status).count
        by_status = Crm::AiStageSuggestion.statuses.keys.index_with { |status| counts[status].to_i }

        auto = by_status['auto_applied']
        accepted = by_status['accepted']
        dismissed = by_status['dismissed']
        ai_influenced = auto + accepted

        {
          period: { since: since.iso8601, until: until_time.iso8601 },
          by_status: by_status,
          ai_auto_moves: auto,
          ai_accepted: accepted,
          ai_dismissed: dismissed,
          ai_influenced_total: ai_influenced,
          acceptance_rate: (accepted + dismissed).zero? ? nil : (accepted.to_f / (accepted + dismissed)).round(4)
        }
      end

      private

      def suggestions
        scope = account.crm_ai_stage_suggestions.where(created_at: range)
        return scope.where(card_id: Crm::Relacao.cards_do_funil(account).where(pipeline_id: pipelines.select(:id)).select(:id)) if todos_os_funis?
        return scope if pipeline.blank?

        scope.where(card_id: Crm::Relacao.cards_do_funil(account).where(pipeline_id: pipeline.id).select(:id))
      end

      def todos_os_funis?
        ActiveModel::Type::Boolean.new.cast(params[:todos_os_funis]) == true
      end
    end
  end
end
