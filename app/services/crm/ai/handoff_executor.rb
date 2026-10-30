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
      # com_ia (#1593): a regra levou a conversa a um agente de IA; o serviço dos Agentes já trocou o dono e avisou.
      STATUS = { entregue: :handed_off, convidado: :invited, segurando: :held_online, com_ia: :handed_to_ai }.freeze
      # O motivo do motor no vocabulário de sempre deste executor (logs e specs).
      ERROS = {
        'ja_tem_pessoa' => 'already_assigned', 'intervalo' => 'cooldown', 'ninguem_cuida' => 'no_eligible_agent',
        'falhou_atribuir' => 'assignment_failed', 'convite_falhou' => 'invite_failed', 'fechada' => 'no_conversation',
        'ninguem_online' => 'no_online_agent', 'presenca_indisponivel' => 'presence_unavailable',
        'nao_conseguimos_chamar' => 'nobody_reached'
      }.freeze
      # #1673 (decisão do Rodrigo, 16/10): com um agente nosso no nome, o pedido de pessoa é dele (bot_handoff! pela
      # instrução); a IA do CRM não tira a conversa por conta própria. Só quando o agente pode responder agora (o dono
      # do QuemResponde): espelho de vínculo arquivado ou de agente pausado não segura a conversa, senão ela ficaria sem
      # ninguém. O n8n e a conversa sem robô seguem como antes. A fila da conversa (HandoffDrainJob) usa a mesma regra.
      # Exceção (IA entende a conversa F1, flag `crm_ia_fatos_da_conversa`, regra f do Rodrigo): o nosso assistente já
      # prometeu ao cliente que uma pessoa vai assumir, ninguém assumiu e o problema não foi resolvido depois
      # (`handoff.promised_by_our_assistant`, lido pelo modelo). A promessa é um fato à parte da intenção (`intent`), e
      # só vale com um agente nosso dono da conversa (o caso do #1673): aí a IA do CRM cumpre a promessa pela Entrega de
      # sempre, com as outras guardas valendo (pessoa já atribuída, intervalo, devolução). Sem dono nosso, ou com o agente
      # protegido (`instrucao_mantida?`) dono, a promessa não muda nada. A espera vai com o motivo do pedido do robô
      # (MOTIVO_DA_PROMESSA): foi o robô que prometeu, e a fila (HandoffDrainJob) não larga a espera de volta para ele.
      OWNED_BY_OUR_AGENT = 'owned_by_our_agent'.freeze
      MOTIVO_DA_ENTREGA = 'ia_crm'.freeze
      MOTIVO_DA_PROMESSA = 'robo_pediu'.freeze

      # pelo_card (#1693, decisão 1a do Rodrigo, 16/10): numa mensagem de vários assuntos, o pedido vai pela regra do card
      # a que o cliente o ligou, mesmo fora do foco, enquanto ele seguir aberto nesta conversa; senão, pela regra do foco.
      # tentativa (#2154): a da avaliação depois da fala do agente, para o teto do reagendamento.
      def initialize(card:, handoff:, trigger: 'message', pelo_card: false, tentativa: 0)
        @tentativa = tentativa
        @card = card
        @handoff = normalize(handoff)
        @trigger = trigger
        @pelo_card = pelo_card
        # A CONVERSA VIVA, e não a primária do card (issue #553): com card por contato, a primária é a primeira conversa
        # dele, e o responsável ia parar lá enquanto o cliente esperava na conversa nova.
        @conversation = card.conversa_em_atendimento
      end

      def perform
        blocked = blocked_reason
        return skip_blocked(blocked) if blocked
        return fala_em_curso if fala_em_curso?

        # Decisão do Rodrigo (16/10, opção a): o card do pedido saiu da conversa (fechou) e o cliente pediu gente;
        # alguém recebe, pela regra do foco. A linha deixa contar quantas vezes isso acontece.
        registrar('desvio', motivo: 'pedido_card_fechado_foco') if @pelo_card && !Crm::Assunto.da_conversa?(@card, @conversation)
        motivo = promessa_a_cumprir? || depois_da_fala_do_agente? ? MOTIVO_DA_PROMESSA : MOTIVO_DA_ENTREGA
        entrega = Crm::Entrega.new(conversation: @conversation, card: @card, motivo: motivo, origem: @trigger, pelo_card: @pelo_card,
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

        conversa_bloqueada
      end

      def conversa_bloqueada
        # #1606 (corrida c): a avaliação leva de 15 a 25 s; se o assunto da conversa virou outro card nesse meio tempo,
        # não passa pelo card antigo. A regra é a mesma da entrega (Crm::Assunto.funil_atual).
        # Com pelo_card, quem escolhe a regra é a Entrega: a do card do pedido, ou a do foco se ele saiu da conversa.
        return 'assunto_mudou' unless @pelo_card || Crm::Assunto.atual?(@card, @conversation)
        return 'already_assigned' if @conversation.assignee_id.present?
        return OWNED_BY_OUR_AGENT if agente_nosso_segura?
        # Devolvida à IA por um humano e sem nada novo desde então: a "transferência" que a IA leu é a fala antiga.
        return 'devolvida_sem_pedido_novo' if Crm::Ai::DevolucaoAIa.sem_pedido_novo?(@card, @conversation)
        return 'cooldown' if registro.intervalo_ativo?

        nil
      end

      def agente_nosso_segura?
        return false if dono_ativo.nil?
        return true unless promessa_a_cumprir? || depois_da_fala_do_agente?

        registrar(promessa_a_cumprir? ? 'promessa_do_robo' : 'depois_da_fala_do_agente', motivo: OWNED_BY_OUR_AGENT)
        false
      end

      def dono_ativo
        return @dono_ativo if defined?(@dono_ativo)

        @dono_ativo = ::Autonomia::Agents::QuemResponde.dono_ativo(@conversation)
      end

      # A promessa só conta com a flag, com um agente nosso dono da conversa e que não seja o protegido.
      def promessa_a_cumprir?
        return @promessa_a_cumprir if defined?(@promessa_a_cumprir)

        @promessa_a_cumprir = FatosDaConversa.ligada?(@card.account) && FatosDaConversa.promessa?(@handoff) &&
                              dono_ativo.present? && !dono_ativo.agent&.instrucao_mantida?
      end

      # #2154 (flag `agente_so_informa`, regra do Rodrigo de 24/10): o agente nosso não passa mais a conversa; avisou o
      # cliente e a fala já saiu (Crm::Ai::AvaliacaoDepoisDaFala). Nesta avaliação a IA de Atribuição decide com o agente
      # no nome. Como na promessa, a espera vai com o motivo do pedido do robô (MOTIVO_DA_PROMESSA): a fila
      # (HandoffDrainJob) não a larga de volta para o agente, que segue no nome até alguém receber. Os outros gatilhos
      # (a mensagem do cliente, que roda antes da fala) seguem com o bloqueio do #1673.
      def depois_da_fala_do_agente?
        return @depois_da_fala_do_agente if defined?(@depois_da_fala_do_agente)

        @depois_da_fala_do_agente = @trigger == AvaliacaoDepoisDaFala::TRIGGER && dono_ativo.present? &&
                                    ::Autonomia::Agents::AgenteSoInforma.ligada?(@card.account)
      end

      # #2154 (revisões): o modelo leva de 15 a 25 s, e nesse meio tempo o cliente pode ter escrito e o agente estar
      # respondendo o turno seguinte (debounce, IA ou pedaços: Autonomia::Agents::Operate::TurnoEmCurso). Entregar agora
      # faria a resposta se perder ou cortaria a fala no meio: a avaliação volta depois, com teto de tentativas
      # (AvaliacaoDepoisDaFala.reagendar), sem mexer na espera.
      def fala_em_curso?
        depois_da_fala_do_agente? && AvaliacaoDepoisDaFala.fala_em_curso?(@conversation)
      end

      def fala_em_curso
        AvaliacaoDepoisDaFala.reagendar(@card, @conversation, @tentativa)
        skip('fala_em_curso')
      end

      def depois_da_entrega(entrega)
        status = STATUS[entrega.status]
        return skip(erro_de(entrega)) if status.nil?

        apos_entregar if status == :handed_off
        # A espera agora fica na conversa (Crm::Entrega::Marca); a do card, anterior ao #1454, sai. Com um agente de IA
        # (#1593) também: a conversa já tem dono.
        clear_handoff_hold! if %i[held_online handed_to_ai].include?(status)
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
      # IA entende a conversa F1: a promessa do nosso assistente a cumprir também é pedido (promessa_a_cumprir?).
      def requested?
        pedido_do_modelo? || promessa_a_cumprir?
      end

      def pedido_do_modelo?
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
