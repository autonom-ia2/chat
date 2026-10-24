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
        # `escolhas_incompletas` (#380): o Agente de Cotação emudeceu porque as escolhas da corretora no
        # config estão incompletas — o motivo fica no evento com o próprio nome, não colapsado em `other`.
        ALLOWED_REASONS = %w[low_confidence ai_unavailable human_requested missing_knowledge policy audience schedule
                             escolhas_incompletas assunto_atrasou recuperada_tarde recuperacao_falhou
                             recuperacao_acordar_falhou recuperacao_passagem_falhou recuperada_so_contexto other].freeze

        # Porta de engajamento (#284 · Entrega 2a): a conversa foi passada DIRETO para humanos sem
        # resposta. `reason` ∈ audience | schedule -> event_type skipped_audience | skipped_schedule.
        def self.skipped(agent:, conversation:, reason:)
          create!(
            agent: agent, conversation: conversation, event_type: :"skipped_#{reason}",
            handoff_reason: curate_code(reason)
          )
        end

        # #1669: a IA calou porque uma pessoa da equipe respondeu a mensagem `message_id` do cliente. Ids e a etapa (rótulo
        # nosso), nunca nome nem texto. Uma vez por mensagem do cliente, conferido antes de gravar; sem índice único (sem
        # migration), uma duplicata rara na corrida é aceita.
        def self.silenciado_pessoa_respondeu(agent:, conversation:, message_id:, etapa:)
          return if message_id.blank?
          return if agent.events.silenciado_pessoa_respondeu.exists?(conversation_id: conversation&.id, message_id: message_id)

          create!(agent: agent, conversation: conversation, event_type: :silenciado_pessoa_respondeu,
                  message_id: message_id, metadata: { 'etapa' => etapa.to_s })
        rescue ActiveRecord::ActiveRecordError => e
          Rails.logger.warn("[autonomia][events] log_skipped agent=#{agent&.id} #{e.class}")
          nil
        end

        # `message` = a Message outgoing postada (liga o evento ao feedback do atendente).
        # Fontes por resposta (#284): só os IDs dos knowledge_entries citados + o modelo — nunca o
        # conteúdo do trecho (já vive em knowledge_entries) nem prompt/instruction.
        # `metadata`: os ids dos fatos de memória enviados ao modelo (#1755, `memoria_fact_ids`), como os used_entry_ids.
        def self.replied(agent:, conversation:, result:, message: nil, metadata: {})
          create!(
            agent: agent, conversation: conversation, event_type: :replied,
            confidence: result&.confidence,
            answered_from_knowledge: result&.answered_from_knowledge || false,
            message_id: message&.id,
            used_entry_ids: used_entry_ids(result),
            model: ::Autonomia::Agents::Config::ANSWERER_MODEL,
            metadata: metadata.to_h
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

        # #2154 (flag `agente_so_informa`): o agente avisou o cliente que vai chamar alguém e seguiu atendendo; quem decide
        # passar é a IA de Atribuição. Registro do turno, não passagem, gravado quando a fala sai de fato (a mensagem única,
        # ou o 1º pedaço). `reason`: o código já curado que a entrega em pedaços leva no meta; senão, o do result. O motivo
        # passa pela mesma allowlist do handed_off.
        def self.avisou_que_chama_alguem(agent:, conversation:, result: nil, reason: nil, message: nil)
          create!(agent: agent, conversation: conversation, event_type: :avisou_que_chama_alguem,
                  handoff_reason: reason.present? ? curate_code(reason) : curated_reason(result), message_id: message&.id)
        end

        # #2154: a fala do agente que avisou saiu, mas a IA de Atribuição não vai avaliar (sem card, funil sem passagem,
        # IA do funil desligada, sem credencial...). Sem isto, o cliente ouviria "vou chamar alguém" e ninguém viria, em
        # silêncio. `motivo`: rótulo de lista fechada do CRM (Crm::Ai::AvaliacaoDepoisDaFala), nunca texto.
        def self.atribuicao_nao_avaliou(conversation:, motivo:)
          agent = ::Autonomia::Agents::QuemResponde.agent_inbox(conversation)&.agent
          return if agent.blank?

          create!(agent: agent, conversation: conversation, event_type: :atribuicao_nao_avaliou, metadata: { 'motivo' => motivo.to_s })
        end

        # Handoff operacional (ex.: Crm::Ai::HandoffExecutor) numa caixa que pode ou não ter agente
        # Autonom.ia: resolve o vínculo pela caixa/conta da conversa e registra só se houver. nil se não.
        def self.handed_off_by_inbox(conversation:, reason:)
          return if conversation.blank?

          agent_inbox = ::Autonomia::Agents::QuemResponde.agent_inbox(conversation)
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
