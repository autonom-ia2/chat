module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — ouve `message.created` e dispara a resposta do agente
      # nativo. ESPELHA o mecanismo do CRM (`Crm::ConversationObserverListener`):
      # herda de BaseListener (Singleton), registra-se no array `listeners` do
      # AsyncDispatcher (Sidekiq), e SÓ enfileira um job — toda decisão cara
      # (DB/estado/IA) vive no ReplyJob.
      #
      # ANTI-LOOP / ZERO REGRESSÃO: este listener só age para mensagens INCOMING,
      # públicas (não private) e não-activity, com a feature flag ligada. A
      # resposta OUTGOING do próprio bot (sender AgentBot) NUNCA é incoming, logo
      # nunca re-dispara o processamento. Em qualquer outro caso: no-op silencioso
      # e barato (sem tocar o core de mensagens).
      class MessageListener < BaseListener
        def message_created(event)
          message = event.data[:message]
          return if ignored?(message)

          # Gate POR CONTA: ENV master + feature `autonomia_agents` da conta DESTA
          # mensagem (rodamos fora de request, sem Current.account). message.account
          # é o caminho canônico do core; a conta certa é a dona da conversa/inbox.
          return unless ::Autonomia::Agents::Config.enabled?(message.account)
          return skip_unsupported(message) if unsupported?(message)

          # vínculo (AgentInbox) + agent.enabled?/active? + conversa pending +
          # unassigned são checados no Job (precisam de DB). Aqui só o mínimo barato.
          ::Autonomia::Agents::Operate::ReplyJob.perform_later(message.conversation_id, message.id)
        end

        private

        def ignored?(message)
          message.blank? ||
            !message.incoming? ||      # ANTI-LOOP: só mensagens do contato disparam
            message.private? ||        # nunca processa notas privadas
            message.activity? ||       # eventos de atividade não são respondíveis
            message.conversation_id.blank?
        end

        # Aviso de "mensagem não suportada" do WhatsApp (chat#1489), na conta com a flag `whatsapp_hybrid_recovery`:
        # não há o que responder. Quando o WhatsApp API recupera o conteúdo, quem decide chamar a IA, uma vez, é o
        # WhatsappHybrid::RecoveryAiWake. Sem a flag, igual à main. Instagram e TikTok também marcam `is_unsupported` (em
        # mídia); lá a IA segue como antes.
        def unsupported?(message)
          message.inbox&.channel_type == 'Channel::Whatsapp' &&
            message.content_attributes.to_h.with_indifferent_access[:is_unsupported].present? &&
            message.account.feature_enabled?(::WhatsappHybrid::UnsupportedRecovery::FEATURE)
        end

        # Sem recuperação em curso, a IA não responde e o motivo fica no evento do agente (sem falha silenciosa). Com
        # recuperação pendente, quem decide (chamar, `recuperada_tarde` ou `recuperacao_falhou`) é a própria recuperação.
        def skip_unsupported(message)
          return if ::WhatsappHybrid::UnsupportedRecovery.pending?(message)

          ::Autonomia::Agents::Operate::NaoSuportada.ignorada(message)
        end
      end
    end
  end
end
