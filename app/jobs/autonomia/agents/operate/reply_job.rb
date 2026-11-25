module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — DEBOUNCE. Coalesce a rajada de mensagens do contato (várias
      # linhas seguidas) em UMA resposta sobre o contexto mais recente, via token-guard
      # com `additional_attributes['autonomia_debounce']` + re-enqueue (last-writer-wins).
      #
      # Mecanismo (2 fases, mesmo job):
      #   - 'trigger' (disparado pelo MessageListener a cada incoming): roda os guards de
      #     estado; grava o stamp com o `pending_message_id` desta mensagem; reagenda a si
      #     mesmo com wait = OPERATE_DEBOUNCE_SECONDS na fase 'settle'.
      #   - 'settle' (após a janela): relê o stamp. Se o `pending_message_id` NÃO bate mais
      #     com este `message_id`, uma mensagem mais nova chegou e já reagendou -> ABORTA
      #     (idempotente). Se ainda bate, chama o Responder UMA vez.
      #
      # ZERO REGRESSÃO / ANTI-LOOP: toda decisão cara (DB/estado/IA) vive aqui, não no
      # listener. No-op barato e silencioso se a conversa não estiver elegível. O stamp é
      # gravado com `update_column` (sem callbacks) -> NUNCA re-dispara MESSAGE_CREATED nem
      # observers. A resposta outgoing do bot não é incoming, logo nunca volta a este job.
      class ReplyJob < ApplicationJob
        # MEDIUM, NÃO LOW (Rodrigo, 23/09/2026): as filas do Sidekiq são de prioridade estrita, e a `low` só anda
        # com as de cima vazias. Com várias cotações em curso, a `medium` (as consultas da cotação) quase nunca
        # esvazia, e a resposta da Lia ao cliente esperava atrás delas.
        queue_as :medium

        DEBOUNCE_KEY = 'autonomia_debounce'.freeze

        # A marca do debounce aponta para esta mensagem: nenhuma mais nova do cliente abriu outro turno (#1606).
        def self.turno_pendente?(conversation, message_id)
          stamp = conversation.additional_attributes.to_h[DEBOUNCE_KEY]
          stamp.is_a?(Hash) && stamp['pending_message_id'] == message_id.to_i
        end

        # #1606: uma mensagem mais nova do cliente abriu outro turno (a marca do debounce aponta para ela), e a resposta do
        # turno desta mensagem ficou velha. Só com a Fase 2 ou com a fila do agente (#3211, `conversa_em_fila`); fora
        # delas, nunca (posta como sempre). Sem marca, segue. Critério único da hora de postar (Responder#turno_superado?)
        # e da entrega da consulta em segundo plano (Tools::ConsultaNoTurno::TurnoSuperado). Ler com a conversa fresca.
        def self.turno_superado?(conversation, message_id, agent)
          return false if message_id.blank?
          return false unless ::Autonomia::Agents::Fase2.ligada?(conversation.account) || ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent)

          stamp = conversation.additional_attributes.to_h[DEBOUNCE_KEY]
          pendente = stamp.is_a?(Hash) ? stamp['pending_message_id'] : nil
          pendente.present? && pendente.to_s != message_id.to_s
        end

        # `posse` (#1606): o id do vínculo cuja posse do turno quem enfileirou já tomou (Operate::ReenfileirarTurno).
        def perform(conversation_id, message_id, phase = 'trigger', posse = nil)
          conversation = Conversation.find_by(id: conversation_id)
          return if conversation.blank?

          # Gate POR CONTA: ENV master + feature da conta DONA da conversa. Job roda
          # fora de request (sem Current.account); a conta certa é conversation.account.
          # Re-checado aqui (e não só no listener) porque a feature pode ter sido
          # desligada na janela entre o enqueue e a execução -> para de responder.
          return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

          agent_inbox = eligible_agent_inbox(conversation)
          return sem_quem_responda(conversation, message_id, phase) if agent_inbox.blank?

          return passagem(conversation, agent_inbox, message_id, posse) if phase == ::Autonomia::Agents::Operate::AoReceberPassagem::FASE
          return trigger(conversation, agent_inbox, message_id) unless phase == 'settle'

          settle(conversation, agent_inbox, message_id, posse)
        end

        private

        # Contrato CANÔNICO de elegibilidade (sem responsável + agente ligado/ativo/não-interno/
        # não-sistema + allowlist; status irrelevante) — fonte única em Operate.eligible_agent_inbox,
        # reusada no momento de postar (Responder/ChunkedDelivery) para revalidar com estado fresco.
        def eligible_agent_inbox(conversation)
          ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)
        end

        # Fase 'trigger': grava o stamp (last-writer-wins) e agenda o settle. Cada incoming
        # nova sobrescreve `pending_message_id` e reagenda; só o último settle prossegue.
        # Janela CONFIGURÁVEL por agente (config['debounce_seconds']), default OPERATE_DEBOUNCE_SECONDS. #3211 (P1, opção
        # `conversa_espera_a_fala`): a janela é o fim previsto da fala anterior (EsperaDaFala.da_rajada); desligada, a de sempre.
        def trigger(conversation, agent_inbox, message_id)
          espera = ::Autonomia::Agents::Operate::EsperaDaFala.da_rajada(agent: agent_inbox.agent, conversation_id: conversation.id)
          stamp_debounce(conversation, message_id, espera)
          abrir_turno(conversation, agent_inbox, message_id)
          self.class.set(wait: espera).perform_later(conversation.id, message_id, 'settle')
        end

        # Fase 'settle': só prossegue se este ainda é o último trigger da janela. Com a Fase 2 (#1606), espera o
        # assunto ser decidido (reagenda a si mesma, sem sleep) e responde no máximo uma vez por dono (PosseDoTurno).
        # Quem responde é o `agent_inbox` relido nesta execução (perform), nunca o de uma rodada anterior. #3211 (P2, opção
        # `conversa_em_fila`): outro turno falando, espera na fila ANTES do assunto (que costuma ser decidido enquanto isso;
        # o EsperaDoAssunto lê o marco uma vez só) e antes da posse (o settle da fila não toma o turno).
        def settle(conversation, agent_inbox, message_id, posse)
          return unless current_token?(conversation, message_id)
          return esperar_na_fila(conversation, message_id, posse) if na_fila?(conversation, agent_inbox, message_id)
          return esperar_o_assunto(conversation, message_id, posse) if esperar_o_assunto?(conversation, agent_inbox, message_id)
          return posse_ja_tomada(conversation, agent_inbox, message_id) unless assumir_o_turno?(conversation, agent_inbox, message_id, posse)

          responder(conversation, agent_inbox, message_id, posse)
        end

        # #2154: outro settle tem a posse deste turno. A marca só sai se o turno já foi respondido (há resposta do robô a
        # esta mensagem); se o outro settle ainda está na IA, a marca é dele e fica.
        def posse_ja_tomada(conversation, agent_inbox, message_id)
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)
          return unless ::Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox,
                                                                    reply_to_message_id: message_id).respondida?

          soltar_turno(conversation, message_id)
        end

        def assumir_o_turno?(conversation, agent_inbox, message_id, posse)
          ::Autonomia::Agents::Operate::PosseDoTurno.assumir?(conversation: conversation, agent_inbox: agent_inbox,
                                                              message_id: message_id, job_id: job_id, posse: posse)
        end

        # #2154: o turno acaba aqui, por qualquer caminho (resposta, silêncio, falha, ou um prepend do Responder que pula o
        # turno sem chegar ao corpo dele, como o Waha::RichNative::AgentTurnGuard), e a marca dele sai. Fica só quando o
        # turno segue: a cadeia de pedaços assumiu a marca, ou o dono novo refaz o turno. #3211: o mesmo vale para a fala
        # (FalaEmCurso), que fica só com a cadeia de pedaços agendada.
        def responder(conversation, agent_inbox, message_id, posse)
          ocupar_a_fala(conversation, agent_inbox, message_id)
          responder = ::Autonomia::Agents::Operate::Responder.new(
            conversation: conversation,
            agent_inbox: agent_inbox,
            reply_to_message_id: message_id,
            posse: ::Autonomia::Agents::Operate::PosseDoTurno.valor(job_id: job_id, posse: posse, agent_inbox: agent_inbox)
          )
          responder.perform
        ensure
          soltar_a_fala(conversation, message_id, responder)
          fim_do_turno(conversation, message_id, responder)
        end

        # #3211 (P2): enquanto este turno fala (a IA e a entrega), o turno novo da conversa espera na fila.
        def ocupar_a_fala(conversation, agent_inbox, message_id)
          return unless ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent_inbox.agent)

          ::Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, message_id, agent_inbox.agent)
        end

        # Solta sem olhar a opção: desligada no meio do turno, a marca ficaria presa e todo turno novo esperaria o teto da
        # fila. Só solta a marca deste turno (sem marca, nada). A cadeia de pedaços agendada fica com ela e solta no fim.
        def soltar_a_fala(conversation, message_id, responder)
          return if responder&.cadeia_agendada?

          ::Autonomia::Agents::Operate::FalaEmCurso.soltar(conversation.id, message_id)
        end

        # Sem a marca (`TurnoEmCurso.marcar?`), nada (nem pergunta ao Responder).
        def fim_do_turno(conversation, message_id, responder)
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)
          return if responder&.turno_segue?

          ::Autonomia::Agents::Operate::TurnoEmCurso.soltar(conversation.id, message_id)
        end

        # Fase 'passagem' (#1630): o turno sem mensagem nova do cliente. O segundo argumento do job é o id da PASSAGEM, não
        # de uma mensagem (AoReceberPassagem.rodar confere de novo o gate, a passagem, o dono e o cliente ativo).
        def passagem(conversation, agent_inbox, passagem_id, posse)
          ::Autonomia::Agents::Operate::AoReceberPassagem.rodar(conversation, agent_inbox, passagem_id, posse)
        end

        def esperar_o_assunto?(conversation, agent_inbox, message_id)
          ::Autonomia::Agents::Operate::EsperaDoAssunto.esperar?(conversation: conversation, agent_inbox: agent_inbox,
                                                                 message_id: message_id)
        end

        def esperar_o_assunto(conversation, message_id, posse)
          self.class.set(wait: ::Autonomia::Agents::Operate::EsperaDoAssunto::INTERVALO)
              .perform_later(conversation.id, message_id, 'settle', posse)
        end

        def na_fila?(conversation, agent_inbox, message_id)
          ::Autonomia::Agents::Operate::EsperaDaFala.na_fila?(agent: agent_inbox.agent, conversation: conversation, message_id: message_id)
        end

        # #3211 (P2): volta daqui a pouco, com a mesma posse, sem responder; a fila desiste no prazo (EsperaDaFala.na_fila?).
        def esperar_na_fila(conversation, message_id, posse)
          self.class.set(wait: ::Autonomia::Agents::Operate::EsperaDaFala::INTERVALO_DA_FILA)
              .perform_later(conversation.id, message_id, 'settle', posse)
        end

        # Grava SÓ a chave do debounce via jsonb_set no servidor (merge per-chave, não
        # overwrite do blob): preserva chaves escritas concorrentemente por outros writers
        # async na mesma conversa (ex.: automation_rule_listener, conversation_language).
        # update_all -> SEM callbacks/validations -> não dispara MESSAGE_CREATED/observers
        # (anti-loop) e é barato. Sobrescrever a coluna inteira com uma cópia stale
        # apagaria essas chaves (perda de dados concorrente). #3211: `espera_ms` é a espera desta rajada; o prazo da fila
        # (EsperaDaFala.na_fila?) conta dela.
        def stamp_debounce(conversation, message_id, espera)
          stamp = { 'pending_message_id' => message_id, 'at' => Time.current.to_f, 'espera_ms' => (espera.to_f * 1000).round }
          Conversation.where(id: conversation.id).update_all(
            [
              "additional_attributes = jsonb_set(COALESCE(additional_attributes, '{}'::jsonb), " \
              "ARRAY[?], ?::jsonb, true)",
              DEBOUNCE_KEY, stamp.to_json
            ]
          )
        end

        # #2154 (flag `agente_so_informa`): o turno começa na mensagem do cliente, para a IA de Atribuição não entregar a
        # conversa enquanto o agente responde (Operate::TurnoEmCurso). A mensagem mais nova toma a marca. #1430: também
        # com a consulta em segundo plano, para o resultado dela não passar na frente da fala do turno. #3211: o teto é o
        # do agente (com as opções da paridade desligadas, o de sempre).
        def abrir_turno(conversation, agent_inbox, message_id)
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)

          ::Autonomia::Agents::Operate::TurnoEmCurso.abrir(conversation.id, message_id, agent_inbox.agent)
        end

        # O settle de um turno que já não tem quem responda (uma pessoa assumiu, o agente saiu) solta a marca dele.
        def sem_quem_responda(conversation, message_id, phase)
          soltar_turno(conversation, message_id) if phase == 'settle'
        end

        def soltar_turno(conversation, message_id)
          return unless ::Autonomia::Agents::Operate::TurnoEmCurso.marcar?(conversation.account)

          ::Autonomia::Agents::Operate::TurnoEmCurso.soltar(conversation.id, message_id)
        end

        # Relê o stamp do banco e compara o token. Mensagem mais nova => token diferente => aborta.
        def current_token?(conversation, message_id)
          conversation.reload.additional_attributes
                      .to_h.dig(DEBOUNCE_KEY, 'pending_message_id') == message_id
        end
      end
    end
  end
end
