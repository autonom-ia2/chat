module Autonomia
  module Agents
    module Operate
      # ENTREGA HUMANIZADA — ORQUESTRADOR. Recebe a resposta JÁ quebrada (ReplyChunker) e entrega
      # pedaço a pedaço com "digitando" + pausa entre eles, imitando um humano — o que antes só existia
      # no fluxo n8n. NÃO usa sleep: cada chunk é um job que, ao postar, agenda o PRÓXIMO via perform_in
      # (worker livre, ordem garantida por encadeamento). Roda só no caminho autonomia (agente nativo).
      #
      # GUARDAS A CADA CHUNK (espelham o "Pre Text Gate Eval" do n8n):
      #   - TURN-TOKEN: se chegou uma mensagem NOVA do cliente durante a entrega (o stamp de debounce
      #     do ReplyJob mudou), ABORTA o resto — o agente não "fala sozinho"; o novo settle responde.
      #   - ELEGIBILIDADE FRESCA: se um humano assumiu (deixou de pending/atribuiu), para e limpa typing.
      #   - IDEMPOTÊNCIA por (reply_to_message_id, chunk_index) via token composto em content_attributes:
      #     retry do Sidekiq nunca duplica um pedaço.
      #
      # SEGURANÇA/IP: só o texto destinado ao cliente vai à mensagem; nada de instruction/prompt.
      class ChunkedDeliveryJob < ApplicationJob
        queue_as :low

        def perform(conversation_id, agent_inbox_id, reply_to_message_id, chunks, index = 0, meta = {})
          conversation = Conversation.find_by(id: conversation_id)
          return if conversation.blank?
          return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

          agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(id: agent_inbox_id)
          return if agent_inbox.blank? || agent_inbox.agent.blank?

          deliver(conversation, agent_inbox, reply_to_message_id, Array(chunks), index.to_i, meta || {})
        end

        private

        def deliver(conversation, agent_inbox, reply_to_message_id, chunks, index, meta)
          typing = ::Autonomia::Agents::Operate::TypingIndicator.new(conversation: conversation, agent_inbox: agent_inbox)
          chunk = chunks[index]

          # Cliente mandou nova mensagem durante a entrega, ou um humano assumiu, ou acabaram os chunks:
          # limpa o "digitando" e encerra esta cadeia. (O novo settle do ReplyJob cuida da nova mensagem.)
          if chunk.blank? || !current_turn?(conversation, reply_to_message_id) || !bot_in_command?(conversation, agent_inbox)
            typing.off
            return
          end

          typing.off # a pausa ANTES deste pedaço já passou; estamos prestes a postar
          posted = post_chunk!(conversation, agent_inbox, reply_to_message_id, index, chunk['text'].to_s)
          # Não postou (re-check no lock reprovou: humano assumiu / agente desligado / turno mudou / já
          # postado): ENCERRA a cadeia — não agenda o próximo pedaço nem deixa "digitando" pendurado.
          return unless posted

          # Fase F: registra "respondido" só uma vez, quando o 1º pedaço entra de fato (message_id = 1º pedaço).
          log_replied(agent_inbox.agent, conversation, meta, posted) if index.zero?

          schedule_next(conversation, agent_inbox, reply_to_message_id, chunks, index, meta, typing)
        end

        # Agenda o próximo pedaço após sua pausa, mostrando "digitando" durante a espera.
        def schedule_next(conversation, agent_inbox, reply_to_message_id, chunks, index, meta, typing)
          nxt = index + 1
          next_chunk = chunks[nxt]
          if next_chunk.blank?
            typing.off
            return
          end

          typing.on
          wait_seconds = (next_chunk['delay_ms'].to_i / 1000.0).clamp(0.1, 30.0)
          self.class.set(wait: wait_seconds.seconds)
              .perform_later(conversation.id, agent_inbox.id, reply_to_message_id, chunks, nxt, meta)
        end

        # Posta UM pedaço como outgoing do AgentBot-espelho. Idempotente por token composto, dentro do
        # lock (NÃO usar return no bloco — dispararia rollback e descartaria a mensagem postada).
        # -> a Message postada, ou nil quando não postou.
        def post_chunk!(conversation, agent_inbox, reply_to_message_id, index, text)
          posted = nil
          conversation.with_lock do
            # Revalidação AUTORITATIVA com estado fresco DENTRO do lock (fecha a corrida entre o check
            # do deliver e o post): turno ainda atual + contrato inteiro (sem responsável, agente
            # ligado/ativo/não-interno/não-sistema, mesma caixa, feature on, allowlist) + idempotência.
            if current_turn?(conversation, reply_to_message_id) &&
               bot_in_command?(conversation, agent_inbox) &&
               !chunk_posted?(conversation, reply_to_message_id, index)
              posted = build_message!(conversation, agent_inbox, reply_to_message_id, index, text)
            end
          end
          posted
        end

        def build_message!(conversation, agent_inbox, reply_to_message_id, index, text)
          Messages::MessageBuilder.new(
            nil, conversation,
            ActionController::Parameters.new(
              content: text, message_type: 'outgoing', sender_type: 'AgentBot',
              sender_id: agent_inbox.agent_bot_id, private: false,
              content_attributes: {
                autonomia_agent_id: agent_inbox.agent.id,
                autonomia_reply_to_message_id: reply_to_message_id,
                autonomia_chunk_index: index,
                autonomia_chunk_token: chunk_token(reply_to_message_id, index)
              }
            )
          ).perform
        end

        # Idempotência: já existe um outgoing do bot com ESTE token (reply_to + chunk_index)? Prefiltra
        # por LIKE (barato, token distintivo) e confirma em Ruby no hash parseado (sem adivinhar o
        # escape do JSON-string dentro da coluna json).
        def chunk_posted?(conversation, reply_to_message_id, index)
          token = chunk_token(reply_to_message_id, index)
          conversation.messages.outgoing.where(sender_type: 'AgentBot')
                      .where('content_attributes::text LIKE ?', "%#{token}%")
                      .any? { |m| m.content_attributes.to_h['autonomia_chunk_token'].to_s == token }
        end

        def chunk_token(reply_to_message_id, index)
          "#{reply_to_message_id}:#{index}"
        end

        # Mesmo token-guard do ReplyJob: o último incoming da janela de debounce ainda é o nosso?
        # Sem stamp (conversa sem debounce, ex.: caminho de teste) -> considera válido (não aborta).
        def current_turn?(conversation, reply_to_message_id)
          stamp = conversation.reload.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
          pending = stamp.is_a?(Hash) ? stamp['pending_message_id'] : nil
          pending.blank? || pending == reply_to_message_id
        end

        def bot_in_command?(conversation, agent_inbox = nil)
          # Revalida o CONTRATO INTEIRO com estado fresco, na MESMA caixa do agente (cada chunk):
          # sem responsável + agente ligado/ativo/não-interno/não-sistema + feature on + allowlist.
          fresh = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)
          fresh.present? && fresh.id == agent_inbox&.id
        end

        def log_replied(agent, conversation, meta, message)
          ::Autonomia::Agents::Operate::EventLogger.create!(
            agent: agent, conversation: conversation, event_type: :replied,
            confidence: meta['confidence'], answered_from_knowledge: meta['answered_from_knowledge'] || false,
            message_id: message.respond_to?(:id) ? message.id : nil,
            used_entry_ids: Array(meta['used_entry_ids']).select { |id| id.is_a?(Integer) },
            model: ::Autonomia::Agents::Config::ANSWERER_MODEL
          )
        end
      end
    end
  end
end
