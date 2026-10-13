module Crm
  module Ai
    # Adaptador da IA do CRM sobre o motor único de entrega (Crm::Entrega, #1454). A IA classificou "transferir": aqui
    # ficam só as guardas que são dela (pedido de verdade, regra ligada, intervalo, "Devolver para a IA") e o que vem
    # depois de entregar (cala o robô, histórico do agente, nota de encaminhamento). Quem recebe e como (pessoa,
    # convite ou segurar até alguém ficar online) é o motor que decide, sob a trava da conversa.
    #
    # Idempotente e à prova de laço: atribuir reenfileira a avaliação (assignee_changed -> SyncConversationCardJob),
    # então as guardas abaixo cortam antes de qualquer efeito.
    class HandoffExecutor
      Result = Struct.new(:status, :assignee, :error, keyword_init: true)
      STATUS = { entregue: :handed_off, convidado: :invited, segurando: :held_online }.freeze
      # O motivo do motor no vocabulário de sempre deste executor (logs e specs).
      ERROS = {
        'ja_tem_pessoa' => 'already_assigned', 'intervalo' => 'cooldown', 'ninguem_cuida' => 'no_eligible_agent',
        'falhou_atribuir' => 'assignment_failed', 'convite_falhou' => 'invite_failed', 'fechada' => 'no_conversation',
        'ninguem_online' => 'no_online_agent'
      }.freeze

      def initialize(card:, handoff:, trigger: 'message')
        @card = card
        @handoff = normalize(handoff)
        @trigger = trigger
        # A CONVERSA VIVA, e não a primária do card (issue #553): com card por contato, a primária é a primeira conversa
        # dele, e o responsável ia parar lá enquanto o cliente esperava na conversa nova.
        @conversation = card.conversa_em_atendimento
      end

      def perform
        blocked = blocked_reason
        return skip_blocked(blocked) if blocked

        entrega = Crm::Entrega.new(conversation: @conversation, card: @card, motivo: 'ia_crm', origem: @trigger,
                                   pedido: { sugestao: @handoff[:suggested_agent], razao: @handoff[:reason] }).call
        depois_da_entrega(entrega)
      end

      private

      # Primeira guarda que falha (ou nil). Lidas fora da trava de propósito: são baratas e só cortam caminho. O
      # motor relê o atendente SOB a trava (corrida R1 da auditoria: antes uma pessoa ou o rodízio nativo podia
      # atribuir entre esta leitura e a gravação, e o último a gravar vencia).
      def blocked_reason
        return 'not_requested' unless requested?
        return 'disabled' unless settings[:enabled]
        return 'no_conversation' if @conversation.blank?
        return 'already_assigned' if @conversation.assignee_id.present?
        # Devolvida à IA por um humano e sem nada novo desde então: a "transferência" que a IA leu é a fala antiga.
        return 'devolvida_sem_pedido_novo' if Crm::Ai::DevolucaoAIa.sem_pedido_novo?(@card, @conversation)
        return 'cooldown' if registro.intervalo_ativo?

        nil
      end

      def depois_da_entrega(entrega)
        status = STATUS[entrega.status]
        return skip(erro_de(entrega)) if status.nil?

        apos_entregar if status == :handed_off
        # A espera agora fica na conversa (Crm::Entrega::Marca); a do card, anterior ao #1454, sai.
        clear_handoff_hold! if status == :held_online
        # Fora da trava e da transação do card (revisão da chat#665): um erro ao postar não desfaz o convite.
        ::Autonomia::Agents::NotaDoEncaminhamento.postar(@conversation) if status == :invited
        registrar(status == :held_online ? 'held_online' : status.to_s, agente: entrega.pessoa)
        Result.new(status: status, assignee: entrega.pessoa, error: status == :held_online ? erro_de(entrega) : nil)
      end

      def erro_de(entrega)
        ERROS.fetch(entrega.motivo.to_s, entrega.motivo.to_s)
      end

      # O motor já gravou a passagem inteira (pessoa, robô fora, conversa aberta) numa gravação só; aqui só o aviso de
      # passagem, o histórico do agente Autonom.ia e a nota para quem assume (conversa 7057). Os dois últimos são
      # best-effort. Sem um segundo save: na mesma transação (o drain trava a conversa) ele apagaria o ASSIGNEE_CHANGED.
      def apos_entregar
        @conversation.dispatch_bot_handoff_event
        ::Autonomia::Agents::Operate::EventLogger.handed_off_by_inbox(conversation: @conversation, reason: 'human_requested')
        ::Autonomia::Agents::NotaDoEncaminhamento.postar(@conversation)
      end

      def normalize(handoff)
        return {} if handoff.blank?

        handoff.respond_to?(:with_indifferent_access) ? handoff.with_indifferent_access : handoff
      end

      # Só "transferir" dispara. "consultar" fica em standby e "continuar" segue o atendimento. Fallback ao
      # should_handoff legado enquanto respostas antigas (sem intent) circulam.
      def requested?
        intent = @handoff[:intent].to_s
        return true if intent == 'transferir'
        return false if %w[continuar consultar].include?(intent)

        ActiveModel::Type::Boolean.new.cast(@handoff[:should_handoff])
      end

      def settings
        @settings ||= Config.handoff_settings(@card.stage, @card.pipeline)
      end

      def registro
        @registro ||= Crm::Entrega::RegistroNoCard.new(card: @card, conversation: @conversation, settings: settings)
      end

      # TODA SAÍDA DESTE SERVIÇO DEIXA UMA LINHA (21/09/2026: uma escalada terminou na conversa errada e não havia uma
      # linha de log no caminho). Só ids e rótulos de lista fechada, nunca texto do cliente ou do modelo. A decisão do
      # motor tem a linha dela ([crm][entrega]).
      def registrar(desfecho, agente: nil, motivo: nil)
        Rails.logger.info(
          "[crm][handoff] card=#{@card.id} conversa=#{@conversation&.id} " \
          "primaria=#{@card.conversation_id} vivas=#{conversas_vivas} " \
          "modo=#{settings[:handoff_mode]} gatilho=#{@trigger} desfecho=#{desfecho} " \
          "agente=#{agente&.id || '-'} motivo=#{motivo || '-'}"
        )
      end

      # As vivas são as de pé, e não todas as ligadas ao card.
      def conversas_vivas
        @card.linked_conversations
             .where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
             .count
      end

      def skip(reason)
        registrar('skipped', motivo: reason)
        Result.new(status: :skipped, error: reason)
      end

      # O intervalo é passageiro: a espera antiga no card (anterior ao #1454) fica para o drain tentar depois. Os
      # outros motivos são finais ou refletem a intenção atual do cliente, e limpam essa espera.
      def skip_blocked(reason)
        clear_handoff_hold! unless reason == 'cooldown'
        skip(reason)
      end

      # Espera gravada no card antes do #1454 (hoje a espera fica na conversa, Crm::Entrega::Marca).
      def clear_handoff_hold!
        # Sob a trava do card, relendo o metadata: não apaga um carimbo gravado por outra conexão.
        @card.with_lock do
          metadata = (@card.metadata || {}).deep_dup
          ai = metadata['ai'] || {}
          next unless ai.key?('handoff_hold')

          metadata['ai'] = ai.except('handoff_hold')
          @card.update!(metadata: metadata)
        end
      end
    end
  end
end
