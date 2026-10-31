module Autonomia
  module Agents
    # Namespace-módulo da camada "Operar". Coexiste com o diretório homônimo
    # app/services/autonomia/agents/operate/*.rb (Zeitwerk: módulo + diretório de mesmo nome).
    # Mantém o guard-rail de teste (allowlist), fonte única consumida pelos gates do operate.
    module Operate
      # Predicado CANÔNICO de elegibilidade do operate (modelo instrução-dirigido). Re-deriva o
      # AgentInbox a partir do inbox ATUAL da conversa (a conversa pode ter mudado de caixa) e valida o
      # CONTRATO INTEIRO: feature habilitada na conta + conversa SEM responsável + agente ligado àquela
      # caixa + habilitado + ativo + não-interno + não-sistema + allowlist de teste. STATUS é irrelevante.
      # Usado pelo ReplyJob (decidir agir) E no momento de postar (Responder/ChunkedDelivery), com estado
      # FRESCO, para nunca postar se algo mudou durante a chamada de IA (humano assumiu, agente desligado,
      # conversa movida de caixa). Devolve o AgentInbox ou nil.
      def self.eligible_agent_inbox(conversation)
        return if conversation.blank? || conversation.assignee_id.present?

        authorized_agent_inbox(conversation)
      end

      # O vínculo `agent_inbox` ainda responde a conversa: o contrato inteiro (`eligible_agent_inbox`), com estado fresco,
      # na MESMA caixa do agente. Usado a cada pedaço (ChunkedDeliveryJob) e antes da interação que sai depois do áudio
      # (InteracaoDepoisDoAudio, #1479).
      def self.no_comando?(conversation, agent_inbox)
        fresh = eligible_agent_inbox(conversation)
        fresh.present? && fresh.id == agent_inbox&.id
      end

      # AUTORIZAÇÃO, sem a POSSE DO TURNO (#313). É o contrato inteiro do `eligible_agent_inbox`
      # MENOS a exigência de a conversa estar sem responsável: feature ligada na conta + tenancy
      # fail-closed + agente ligado/ativo/não-interno/não-sistema + allowlist de teste.
      #
      # Existe porque a entrega ASSÍNCRONA não é uma resposta a uma mensagem: é o resultado de algo
      # que o cliente pediu e está esperando. Ter um humano na conversa não pode fazer a cotação
      # sumir — mas TAMBÉM não pode fazer o kill-switch da conta, o desligamento do agente ou a
      # allowlist de piloto sumirem junto. Por isso o assíncrono relaxa UM predicado nomeado, em vez
      # de abandonar o contrato.
      def self.authorized_agent_inbox(conversation)
        return if conversation.blank?
        return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

        # TENANCY FAIL-CLOSED na LEITURA (par do validate do AgentInbox, que só protege a ESCRITA):
        # a query é escopada pela conta da conversa e o agente resolvido precisa ser da MESMA conta.
        # Um vínculo legado/corrompido (criado antes da validação ou por write que burla o Rails)
        # jamais pode fazer a conversa da conta A responder com agente/KB da conta B. Mismatch =>
        # comporta como "sem agente" (nil), nunca 500.
        # QUEM responde (#1433): a porta da caixa ou, com a Fase 2 ligada, o dono da conversa (área). Ponto único.
        agent_inbox = ::Autonomia::Agents::QuemResponde.agent_inbox(conversation)
        return if agent_inbox.nil?

        agent = agent_inbox.agent
        return unless agent && agent.account_id == conversation.account_id
        return unless agent.atende_cliente?
        return unless test_allowlist_permits?(conversation, agent)

        agent_inbox
      end

      # O espelho deste vínculo comanda a conversa (é o ai_assignee, ou a conversa está pending, legado) e ela não
      # está à espera de pessoa: só então uma passagem nova vale. Desde o #1377 o robô segue como ai_assignee depois
      # do `bot_handoff!` e a própria resposta dele reivindica a conversa, então "o espelho saiu" deixou de ser sinal
      # de passagem feita; o sinal é a marca de espera, gravada pelo `bot_handoff!` na mesma gravação e apagada
      # quando uma pessoa entra na conversa (ConversationBotHandoff). Chamar com estado fresco (dentro do with_lock).
      def self.espelho_no_comando?(conversation, agent_inbox)
        return false if conversation.bot_handoff_waiting?

        conversation.assignee_agent_bot_id == agent_inbox.agent_bot_id || conversation.pending?
      end

      # GUARD-RAIL DE TESTE (aditivo, FAIL-CLOSED). Quando o agente tem
      # `config['test_allowlist_phones']` (lista de números), ele SÓ pode atuar em conversas cujo
      # contato tenha telefone (E.164) batendo — só dígitos — com a lista. Permite testar em caixas
      # reais sem tocar clientes de verdade. Sem a lista => true (comportamento normal, zero
      # regressão). Telefone ausente/não-resolvível => FALSE (nunca responde no escuro; grupos
      # @g.us, com phone_number nil, ficam excluídos automaticamente).
      def self.test_allowlist_permits?(conversation, agent)
        list = Array(agent&.config&.dig('test_allowlist_phones'))
               .map { |phone| phone.to_s.gsub(/\D/, '') }.reject(&:blank?)
        return true if list.empty?

        phone = conversation&.contact&.phone_number.to_s.gsub(/\D/, '')
        return false if phone.blank?

        list.include?(phone)
      end
    end
  end
end
