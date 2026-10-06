module Autonomia
  module Agents
    module Knowledge
      # Revalida o MAPA DE TEMAS + confiança geral da base de um agente fora do fluxo de ingestão.
      # Enfileirado quando uma fonte é EXCLUÍDA (SourcesController#destroy): a base mudou, então o
      # topic_map/knowledge_confidence/knowledge_summary precisam refletir só o que restou aprovado.
      # Best-effort: Reviewer.recompute_overall! já faz rescue interno → o job nunca falha por isso.
      class RecomputeOverallJob < ApplicationJob
        queue_as :low

        def perform(agent_id)
          agent = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
          return if agent.blank?

          Reviewer.recompute_overall!(agent)
        end
      end
    end
  end
end
