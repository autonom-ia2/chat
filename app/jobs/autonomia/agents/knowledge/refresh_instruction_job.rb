module Autonomia
  module Agents
    module Knowledge
      # #3 INSTRUÇÃO VIVA (B) — REFRESH DEBOUNCED/COALESCED da instrução quando a KB muda.
      #
      # POR QUE UM JOB DEDICADO (e não chamar o InstructionRefresher direto no recompute_overall!):
      # um upload em rajada (o FE faz Promise.all sobre N arquivos) dispara N IngestJob → ProcessJob,
      # cada um chamando recompute_overall!. Chamar o refresher inline gerava N chamadas LLM de refresh
      # quase simultâneas, todas escrevendo a MESMA coluna `instruction` — caro (N x 1 LLM em vez de 1
      # por "mudança de base") e com corrida last-writer-wins (um refresh que viu a base PARCIAL podia
      # vencer a escrita de outro que viu a base completa, regredindo o escopo).
      #
      # COALESCÊNCIA: cada mudança grava um `refresh_token` novo no agente e enfileira ESTE job com
      # um pequeno `wait` (debounce). Quando o job finalmente roda, ele só age se o `refresh_token` que
      # carrega ainda for o corrente — assim uma rajada de N uploads colapsa em 1 refresh sobre a base
      # já assentada (os jobs anteriores viram no-op por token vencido). É o mesmo padrão last-writer-
      # wins por token usado em outras partes do módulo (ai_guarded_update / sync_token).
      #
      # GUARDA DE GERAÇÃO: além do token, o InstructionRefresher relê o agente no início e só aplica se
      # a foto da base (knowledge_summary) não mudou no meio — defesa em profundidade contra a corrida.
      #
      # Best-effort: o InstructionRefresher faz rescue interno + kill-switch (Config.instruction_auto_
      # refresh?) → o job nunca derruba nada. Rascunhos (sem instruction) são ignorados pelo refresher.
      class RefreshInstructionJob < ApplicationJob
        queue_as :low

        # Debounce: janela curta para a rajada de uploads assentar antes de redigir a instrução.
        DEBOUNCE = 5.seconds

        # Grava um token novo no agente (coalescência) e enfileira o job com debounce. Cada chamada
        # invalida os jobs já agendados para o mesmo agente (token vencido → no-op). Best-effort.
        def self.enqueue(agent, reason:)
          return if agent.blank? || agent.deleted? || agent.instruction.blank? # só agentes FECHADOS; ignora rascunhos

          token = agent.bump_knowledge_refresh_token!
          set(wait: DEBOUNCE).perform_later(agent.id, token, reason.to_s)
        rescue StandardError => e
          Rails.logger.warn("[autonomia][instruction_refresh] enqueue degraded agent=#{agent&.id} #{e.class}")
          nil
        end

        def perform(agent_id, token, reason)
          agent = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
          return if agent.blank?

          # Coalescência: só o ÚLTIMO refresh enfileirado para este agente roda; os anteriores da
          # rajada caem aqui com token vencido e viram no-op.
          return if agent.knowledge_refresh_token.to_s != token.to_s
          return if agent.instruction.blank? # rascunho (instrução removida no meio): ignora

          InstructionRefresher.call(agent, reason: reason.to_sym)
        end
      end
    end
  end
end
