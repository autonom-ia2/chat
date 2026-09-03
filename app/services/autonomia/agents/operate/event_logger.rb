module Autonomia
  module Agents
    module Operate
      # Logging ADITIVO best-effort de eventos de operação (Fase F). NUNCA levanta:
      # qualquer falha é engolida e logada (sem eco de IP/prompt) para jamais quebrar
      # a resposta/handoff. Só é chamado no caminho autonomia (agente nativo).
      class EventLogger
        # IP oculto: NUNCA persistimos o motivo LIVRE do LLM (pode ecoar PII do cliente,
        # conhecimento recuperado ou pedaços de instruction/prompt). Só gravamos um CÓDIGO
        # de uma allowlist fechada; qualquer outra coisa (texto livre, legado, vazio) -> 'other'.
        # `audience`/`schedule` (#284 · Entrega 2a) são os motivos das passadas diretas pela porta de
        # engajamento (eventos skipped_*), para aparecerem em "Principais motivos" da aba Desempenho.
        ALLOWED_REASONS = %w[low_confidence ai_unavailable human_requested missing_knowledge policy audience schedule other].freeze

        # Porta de engajamento (#284 · Entrega 2a): a conversa foi passada DIRETO para humanos sem
        # resposta. `reason` ∈ audience | schedule -> event_type skipped_audience | skipped_schedule.
        def self.skipped(agent:, conversation:, reason:)
          create!(
            agent: agent, conversation: conversation, event_type: :"skipped_#{reason}",
            handoff_reason: curate_code(reason)
          )
        end

        # `message` = a Message outgoing postada (liga o evento ao feedback do atendente).
        # Fontes por resposta (#284): só os IDs dos knowledge_entries citados + o modelo — nunca o
        # conteúdo do trecho (já vive em knowledge_entries) nem prompt/instruction.
        def self.replied(agent:, conversation:, result:, message: nil)
          create!(
            agent: agent, conversation: conversation, event_type: :replied,
            confidence: result&.confidence,
            answered_from_knowledge: result&.answered_from_knowledge || false,
            message_id: message&.id,
            used_entry_ids: used_entry_ids(result),
            model: ::Autonomia::Agents::Config::ANSWERER_MODEL
          )
        end

        # `reason:` (opcional) sobrepõe o motivo do result — usado quando o handoff vem de fora
        # do Answerer (CRM). Passa pela mesma allowlist.
        def self.handed_off(agent:, conversation:, result:, reason: nil)
          create!(
            agent: agent, conversation: conversation, event_type: :handed_off,
            handoff_reason: reason.present? ? curate_code(reason) : curated_reason(result)
          )
        end

        # Handoff operacional (ex.: Crm::Ai::HandoffExecutor) numa caixa que pode ou não ter agente
        # Autonom.ia: resolve o vínculo pela caixa/conta da conversa e registra só se houver. nil se não.
        def self.handed_off_by_inbox(conversation:, reason:)
          return if conversation.blank?

          agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id,
                                                                account_id: conversation.account_id)
          return if agent_inbox&.agent.blank?

          handed_off(agent: agent_inbox.agent, conversation: conversation, result: nil, reason: reason)
        end

        def self.create!(agent:, conversation:, **attrs)
          ::Autonomia::Agents::AgentEvent.create!(
            agent: agent, account_id: agent.account_id,
            conversation_id: conversation&.id, **attrs
          )
        rescue StandardError => e
          Rails.logger.warn("[autonomia][events] log_skipped agent=#{agent&.id} #{e.class}")
          nil
        end

        # Só ids inteiros de knowledge_entries; a "imagem da mensagem" entra em used_knowledge com
        # id nil e fica de fora.
        def self.used_entry_ids(result)
          Array(result&.used_knowledge).filter_map { |entry| entry[:id] || entry['id'] }
                                       .select { |id| id.is_a?(Integer) }.uniq
        end

        # Motivo do handoff é texto LIVRE do LLM (handoff[:reason]) -> potencial IP/PII.
        # NÃO truncamos e persistimos texto livre: colapsamos para um código da allowlist.
        # Códigos conhecidos da Fase B (low_confidence/ai_unavailable) passam direto; tudo
        # mais (texto livre do LLM, valor desconhecido) vira 'other'. Sem result (erro/
        # timeout) -> nil (agrupado como "outros" no analytics).
        def self.curated_reason(result)
          reason = result&.handoff&.dig(:reason)
          return nil if reason.blank?

          curate_code(reason)
        end

        def self.curate_code(reason)
          code = reason.to_s.strip.downcase
          ALLOWED_REASONS.include?(code) ? code : 'other'
        end
      end
    end
  end
end
