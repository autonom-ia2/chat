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
      #     do ReplyJob mudou), ABORTA o resto — o agente não "fala sozinho"; o novo settle responde. Com a opção
      #     `conversa_entrega_inteira` (#3211, só com a fila), só o 1º pedaço confere o turno: depois que a fala começou,
      #     mensagem nova não a corta (o turno novo espera na fila). #3258 (flag `agente_le_no_meio_do_turno`): o texto termina,
      #     mas o comparativo do Seguro Viagem dessa fala fica segurado até o fim do turno novo (`ComparativoSegurado`).
      #   - ELEGIBILIDADE FRESCA: se um humano assumiu (deixou de pending/atribuiu), para e limpa typing.
      #   - IDEMPOTÊNCIA por (reply_to_message_id, chunk_index) via token composto em content_attributes:
      #     retry do Sidekiq nunca duplica um pedaço.
      #
      # SEGURANÇA/IP: só o texto destinado ao cliente vai à mensagem; nada de instruction/prompt.
      class ChunkedDeliveryJob < ApplicationJob
        # MEDIUM, junto do `ReplyJob` (Rodrigo, 23/09/2026): a entrega em pedaços é a mesma resposta ao cliente,
        # e na `low` ela esperava atrás das consultas de cotação.
        queue_as :medium
        FalaDaCadeia = ::Autonomia::Agents::Operate::FalaDaCadeia
        # O turno ainda é este? (`current_turn?`, `bot_in_command?`, `respondida_junto?`)
        include TurnoDoPedaco
        # Os cartões do último pedaço: descarte, retry e o comparativo segurado (#3258).
        include CartoesDoPedaco

        def perform(conversation_id, agent_inbox_id, reply_to_message_id, chunks, index = 0, meta = {})
          @turno_segue = @fala_segue = false
          conversation = Conversation.find_by(id: conversation_id)
          entregar(conversation, agent_inbox_id, reply_to_message_id, chunks, index, meta) if conversation.present?
        ensure
          # #3211: a cadeia é dona da marca da fala (o ReplyJob a deixa quando agenda pedaços). Solta em toda saída: parada
          # por qualquer motivo (inclusive troca de dono, mesmo com o turno refeito: o settle refeito ocupa de novo e solta
          # a sua), último pedaço, retorno antecipado e exceção. Só fica quando o próximo pedaço foi agendado
          # (@fala_segue, renovada em schedule_next). Não depende da opção (ela pode ter sido desligada entre ocupar e
          # soltar); só o próprio turno solta (compare-and-delete). Trade-off na exceção: soltar deixa um turno na fila falar
          # enquanto o Sidekiq refaz o pedaço (janela estreita); não soltar prenderia a marca até o TTL se as tentativas
          # acabarem, e todo turno novo esperaria até 150 s.
          ::Autonomia::Agents::Operate::FalaEmCurso.soltar(conversation_id, reply_to_message_id) unless @fala_segue
        end

        private

        def entregar(conversation, agent_inbox_id, reply_to_message_id, chunks, index, meta)
          return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

          agent_inbox = ::Autonomia::Agents::AgentInbox.kept.find_by(id: agent_inbox_id)
          return if agent_inbox.blank? || agent_inbox.agent.blank?

          deliver(conversation, agent_inbox, reply_to_message_id, Array(chunks), index.to_i, meta || {})
          soltar_o_turno(conversation, reply_to_message_id) unless @turno_segue
        end

        def deliver(conversation, agent_inbox, reply_to_message_id, chunks, index, meta)
          typing = ::Autonomia::Agents::Operate::TypingIndicator.new(conversation: conversation, agent_inbox: agent_inbox)
          chunk = chunks[index]

          # Cliente mandou nova mensagem durante a entrega, ou um humano assumiu, ou acabaram os chunks:
          # limpa o "digitando" e encerra esta cadeia. (O novo settle do ReplyJob cuida da nova mensagem.)
          motivo = chunk.blank? ? :sem_pedaco : motivo_da_parada(conversation, agent_inbox, reply_to_message_id, index, meta)
          typing.off # parando, ou a pausa ANTES deste pedaço já passou e estamos prestes a postar
          posted, motivo = post_chunk!(conversation, agent_inbox, reply_to_message_id, index, chunk, meta) if motivo.nil?
          # Não postou (re-check no lock reprovou: humano assumiu / agente desligado / turno mudou / já
          # postado): ENCERRA a cadeia — não agenda o próximo pedaço nem deixa "digitando" pendurado. Só a troca de
          # dono refaz o turno (nunca "já postado", o retry de um pedaço que entrou).
          if motivo
            descartar_cartoes(conversation, agent_inbox, reply_to_message_id, chunks, motivo)
            reenfileirar_cartoes(conversation, agent_inbox, reply_to_message_id, chunks, index) if motivo == :ja_postado
            return parou(conversation, agent_inbox, reply_to_message_id, index, meta, motivo)
          end

          # Fase F: registra "respondido" só uma vez, quando o 1º pedaço entra de fato (message_id = 1º pedaço).
          primeiro_pedaco(agent_inbox.agent, conversation, meta, posted) if index.zero?
          enfileirar_os_cartoes(posted) # #1479 F3: o último pedaço é a âncora dos cartões

          schedule_next(conversation, agent_inbox, reply_to_message_id, chunks, index, meta, typing)
        end

        # A cadeia parou (o pedaço não foi postado; `posted` só vem sem motivo). A troca de dono pode refazer o turno, a
        # pessoa que respondeu deixa o rastro e (#2154) o cliente que escreveu depois de algum pedaço de uma fala que
        # avisou que vai chamar alguém não impede a avaliação da Atribuição. Os outros motivos só encerram.
        # #3211 (P1) e #3235: a cadeia parou, em qualquer pedaço; a fala acabou e o fim previsto deste turno sai (FalaDaCadeia.acabou).
        def parou(conversation, agent_inbox, reply_to_message_id, index, meta, motivo)
          FalaDaCadeia.acabou(conversation, agent_inbox.agent, reply_to_message_id)
          ::Autonomia::Agents::Operate::LeituraNoTurno.parou_nos_pedacos(conversation: conversation, msg: reply_to_message_id,
                                                                         meta: meta, motivo: motivo, pedaco: index)
          case motivo
          when :dono_mudou then refazer_se_o_dono_mudou(conversation, agent_inbox, reply_to_message_id, index, meta)
          when :pessoa_respondeu then avisar_pessoa_respondeu(agent_inbox, conversation, reply_to_message_id, index)
          when :turno_mudou then pedir_avaliacao(conversation, meta) if index.positive?
          when :respondida_junto then rastro_de_respondida_junto(conversation, reply_to_message_id)
          end
        end

        # #1606: a cadeia parou antes do 1º pedaço porque OUTRO vínculo ativo da caixa virou o dono depois da IA (troca sem
        # evento, como a atribuição de robô pela tela). Sem nada postado, o turno é refeito pelo dono novo, como no
        # Responder (`dono_mudou`); o ReenfileirarTurno confere se o turno ainda é este e barra o segundo enfileiramento.
        # Do 2º pedaço em diante a resposta já começou: a cadeia só para (resposta parcial, aceita). O 1º pedaço já postado
        # (retry do índice 0) também conta como resposta começada. `meta['posse']`: a posse do settle que respondeu, para
        # soltar só a dele (PosseDoTurno.soltar).
        def refazer_se_o_dono_mudou(conversation, agent_inbox, reply_to_message_id, index, meta)
          return unless index.zero? && dono_novo?(conversation, agent_inbox)
          return if chunk_posted?(conversation, reply_to_message_id, 0)

          ::Autonomia::Agents::Operate::ReenfileirarTurno.call(conversation: conversation, message_id: reply_to_message_id,
                                                               origem: :responder, quem_perdeu: agent_inbox,
                                                               posse_de_quem_perdeu: meta['posse'])
          @turno_segue = true # #2154: o mesmo turno segue com o dono novo, com a marca dele
        end

        # -> nil para seguir; senão o motivo de parar (:turno_mudou, :dono_mudou, :ja_postado, :pessoa_respondeu).
        # `ja_postado` vem antes de `pessoa_respondeu`: o retry de um pedaço que já entrou não é silêncio da pessoa.
        # `pessoa_respondeu` (#1669, só com a Fase 2): uma pessoa da equipe respondeu a mensagem do cliente antes deste
        # pedaço; o resto da cadeia não sai. A IA segue na conversa e responde a próxima mensagem do cliente.
        # #3211: o turno ainda é este? Do 2º pedaço em diante, com `conversa_entrega_inteira` (+ fila), a fala já começou e mensagem
        # nova não a corta: vale sem olhar o stamp (FalaDaCadeia.comecada?). O 1º pedaço sempre confere. Elegibilidade,
        # `ja_postado` e `pessoa_respondeu` seguem conferidos em todo pedaço.
        # #3225: `respondida_junto` (1º pedaço, com a flag): o turno que estava falando leu esta mensagem e já respondeu.
        def motivo_da_parada(conversation, agent_inbox, reply_to_message_id, index, meta = {})
          comecada = FalaDaCadeia.comecada?(agent_inbox.agent, conversation.inbox, index)
          return :turno_mudou unless comecada || current_turn?(conversation, reply_to_message_id, meta, agent_inbox.agent)
          return :dono_mudou unless bot_in_command?(conversation, agent_inbox)
          return :ja_postado if chunk_posted?(conversation, reply_to_message_id, index)
          return :respondida_junto if respondida_junto?(conversation, agent_inbox, reply_to_message_id, index)

          :pessoa_respondeu if ::Autonomia::Agents::Operate::PessoaDaEquipe.respondeu_depois?(conversation, reply_to_message_id)
        end

        # Mesmo rastro do silêncio do Responder (ids e rótulo, nada do texto), com o pedaço em que a cadeia parou: o log e
        # o evento (fora do lock; o post_chunk! já devolveu).
        def avisar_pessoa_respondeu(agent_inbox, conversation, reply_to_message_id, index)
          Rails.logger.info("[autonomia][operate] silencio agent=#{agent_inbox.agent.id} conv=#{conversation.id} " \
                            "motivo=pessoa_respondeu pedaco=#{index}")
          ::Autonomia::Agents::Operate::EventLogger.silenciado_pessoa_respondeu(
            agent: agent_inbox.agent, conversation: conversation, message_id: reply_to_message_id, etapa: "pedaco_#{index}"
          )
        end

        def dono_novo?(conversation, agent_inbox)
          return false unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)

          fresh = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)
          fresh.present? && fresh.id != agent_inbox.id
        end

        # Agenda o próximo pedaço após sua pausa, mostrando "digitando" durante a espera.
        def schedule_next(conversation, agent_inbox, reply_to_message_id, chunks, index, meta, typing)
          nxt = index + 1
          next_chunk = chunks[nxt]
          if next_chunk.blank?
            typing.off
            FalaDaCadeia.acabou(conversation, agent_inbox.agent, reply_to_message_id) # #3235: o último pedaço saiu
            pedir_avaliacao(conversation, meta)
            # #3258: o turno acabou de falar; o comparativo que uma fala anterior segurou sai ou é descartado.
            return ::Autonomia::Agents::Operate::ComparativoSegurado.no_fim_do_turno(conversation, agent_inbox.agent, reply_to_message_id)
          end

          typing.on
          wait_seconds = ::Autonomia::Agents::Operate::FalaEmCurso.espera_do_pedaco(next_chunk)
          renovar_o_turno(conversation, reply_to_message_id)
          FalaDaCadeia.renovar(conversation, agent_inbox.agent, reply_to_message_id) # #3211 (P2): a fala segue no próximo pedaço
          self.class.set(wait: wait_seconds.seconds)
              .perform_later(conversation.id, agent_inbox.id, reply_to_message_id, chunks, nxt, meta)
        end

        # O 1º pedaço entrou: o "respondido" de sempre e, se o turno avisou que vai chamar alguém (#2154, marca no meta), o
        # registro do aviso, agora que a fala de fato começou a sair.
        def primeiro_pedaco(agent, conversation, meta, posted)
          log_replied(agent, conversation, meta, posted)
          aviso = meta[::Autonomia::Agents::AgenteSoInforma::META]
          return unless aviso

          ::Autonomia::Agents::AgenteSoInforma.fala_comecou!(agent: agent, conversation: conversation, reason: aviso.to_h['motivo'],
                                                             message: posted)
        end

        # #2154 (flag `agente_so_informa`): o turno avisou que vai chamar alguém (marca no meta, posta pelo Responder) e a fala
        # terminou de sair (o último pedaço, ou o cliente escreveu depois de algum pedaço): a IA de Atribuição lê e decide.
        # Nunca derruba a entrega (AgenteSoInforma.fala_terminou!).
        def pedir_avaliacao(conversation, meta)
          return unless meta[::Autonomia::Agents::AgenteSoInforma::META]

          ::Autonomia::Agents::AgenteSoInforma.fala_terminou!(conversation)
        end

        # #2154 (flag `agente_so_informa`, Operate::TurnoEmCurso): o próximo pedaço vai sair; a marca do turno é renovada
        # ANTES de agendá-lo, só se ainda é deste turno (compare-and-expire), e o turno segue na cadeia.
        def renovar_o_turno(conversation, reply_to_message_id)
          @turno_segue = @fala_segue = true # só schedule_next chama: o próximo pedaço vai ser agendado, a marca fica com a cadeia
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)

          ::Autonomia::Agents::Operate::TurnoEmCurso.renovar(conversation.id, reply_to_message_id)
        end

        # A cadeia terminou, por qualquer motivo: solta a marca, só se ainda é deste turno (compare-and-delete).
        def soltar_o_turno(conversation, reply_to_message_id)
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)

          ::Autonomia::Agents::Operate::TurnoEmCurso.soltar(conversation.id, reply_to_message_id)
        end

        # Posta UM pedaço como outgoing do AgentBot-espelho. Idempotente por token composto, dentro do
        # lock (NÃO usar return no bloco — dispararia rollback e descartaria a mensagem postada).
        # -> [a Message postada, nil] ou [nil, motivo] quando não postou (:turno_mudou, :dono_mudou, :ja_postado).
        # #3225: o 1º pedaço grava as mensagens que o turno leu no meio (as do meta), na mesma transação.
        # #3258: e o pedaço do comparativo, o comparativo segurado (`com_o_comparativo_segurado`), também na mesma transação.
        def post_chunk!(conversation, agent_inbox, reply_to_message_id, index, chunk, meta = {})
          posted = nil
          motivo = nil
          conversation.with_lock do
            # Revalidação AUTORITATIVA com estado fresco DENTRO do lock (fecha a corrida entre o check
            # do deliver e o post): turno ainda atual + contrato inteiro (sem responsável, agente
            # ligado/ativo/não-interno/não-sistema, mesma caixa, feature on, allowlist) + idempotência.
            motivo = motivo_da_parada(conversation, agent_inbox, reply_to_message_id, index, meta)
            lidas = index.zero? ? Array(meta['lidas_no_turno']) : []
            if motivo.nil?
              pedaco = com_o_comparativo_segurado(conversation, agent_inbox, reply_to_message_id, chunk, meta)
              posted = build_message!(conversation, agent_inbox, reply_to_message_id, index, pedaco, lidas)
            end
          end
          [posted, motivo]
        end

        # `rich_message` (#1479): só o último pedaço o traz, com a interação já decidida pelo Responder. Com ele, o conteúdo
        # é o `corpo`; o `text` desse pedaço é a versão em texto inteira, para o worker que ainda não conhece o formato.
        # #1479 F3: a marca dele traz só as referências dos cartões; a mensagem grava os cartões resolvidos pela página.
        def build_message!(conversation, agent_inbox, reply_to_message_id, index, chunk, lidas = [])
          Messages::MessageBuilder.new(
            nil, conversation,
            ActionController::Parameters.new(
              content: (chunk['rich_message'] ? chunk['corpo'] : chunk['text']).to_s, message_type: 'outgoing', sender_type: 'AgentBot',
              sender_id: agent_inbox.agent_bot_id, private: false,
              content_attributes: {
                autonomia_agent_id: agent_inbox.agent.id,
                autonomia_reply_to_message_id: reply_to_message_id,
                autonomia_chunk_index: index,
                autonomia_chunk_token: chunk_token(reply_to_message_id, index),
                **{ RichMessages::KEY => chunk['rich_message'] }.compact,
                # #1479 F2: a marca do pedido de localização (`Interacao.nos_pedacos`); F3: os cartões, resolvidos agora.
                **::Autonomia::Agents::Operate::CartoesDoTurno.marca_resolvida(
                  chunk['marca'].to_h, agent: agent_inbox.agent, conversation_id: conversation.id, msg: reply_to_message_id
                ),
                **::Autonomia::Agents::Operate::LeituraNoTurno.marca(lidas)
              }
            )
          ).perform
        end

        # Idempotência: já existe um outgoing do bot com ESTE token (reply_to + chunk_index)? Prefiltra
        # por LIKE (barato, token distintivo) e confirma em Ruby no hash parseado (sem adivinhar o
        # escape do JSON-string dentro da coluna json).
        def chunk_posted?(conversation, reply_to_message_id, index)
          chunk_message(conversation, reply_to_message_id, index).present?
        end

        # A mensagem já postada deste pedaço, ou nil.
        def chunk_message(conversation, reply_to_message_id, index)
          token = chunk_token(reply_to_message_id, index)
          conversation.messages.outgoing.where(sender_type: 'AgentBot')
                      .where('content_attributes::text LIKE ?', "%#{token}%")
                      .find { |m| m.content_attributes.to_h['autonomia_chunk_token'].to_s == token }
        end

        def chunk_token(reply_to_message_id, index)
          "#{reply_to_message_id}:#{index}"
        end

        def log_replied(agent, conversation, meta, message)
          ::Autonomia::Agents::Operate::EventLogger.create!(
            agent: agent, conversation: conversation, event_type: :replied,
            confidence: meta['confidence'], answered_from_knowledge: meta['answered_from_knowledge'] || false,
            message_id: message.respond_to?(:id) ? message.id : nil,
            used_entry_ids: Array(meta['used_entry_ids']).select { |id| id.is_a?(Integer) },
            model: ::Autonomia::Agents::Config::ANSWERER_MODEL,
            metadata: memoria_do_meta(meta)
          )
        end

        # Os ids dos fatos de memória enviados ao modelo (#1755), quando houve memória no turno. #3225: e as mensagens lidas
        # no meio do turno, com as voltas.
        def memoria_do_meta(meta)
          ids = Array(meta['memoria_fact_ids']).select { |id| id.is_a?(Integer) }
          (ids.empty? ? {} : { 'memoria_fact_ids' => ids }).merge(::Autonomia::Agents::Operate::LeituraNoTurno.do_meta(meta))
        end
      end
    end
  end
end
