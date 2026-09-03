module Autonomia
  module Agents
    module Operate
      # Liga/desliga um agente nativo a um inbox, respeitando a regra de coexistência
      # (um inbox tem Gabriela/webhook OU um agente nativo — nunca os dois).
      #
      # connect: cria AgentBot nativo-espelho (outgoing_url NULL → não dispara webhook),
      #          AgentBotInbox do core (ativa inbox.active_bot? → conversas nascem pending)
      #          e o vínculo Autonomia::Agents::AgentInbox. Tudo em transação.
      # disconnect: destrói o vínculo + AgentBotInbox + AgentBot espelho e libera as conversas
      #             pending ao humano via bot_handoff!.
      class InboxConnector
        Result = Struct.new(:status, :error, :agent_inbox, keyword_init: true) do
          def success?
            status == :ok
          end
        end

        def initialize(agent:, inbox:)
          @agent = agent
          @inbox = inbox
          @account = agent.account
        end

        def perform(connect:)
          connect ? connect! : disconnect!
        end

        private

        def connect!
          # V2.1 — agente INTERNO (copiloto da equipe) NUNCA atende cliente: bloqueia o vínculo de caixa
          # (não cria AgentBot/AgentBotInbox/AgentInbox). Autoridade no backend; a UI esconde como 2ª defesa.
          return Result.new(status: :error, error: :agent_internal_not_connectable) if @agent.actuation_internal?
          return Result.new(status: :error, error: :agent_not_active) unless agent_operable?
          return Result.new(status: :error, error: :inbox_has_webhook_bot) if webhook_bot_present?
          return Result.new(status: :error, error: :inbox_already_connected) if already_connected?

          agent_inbox = nil
          ActiveRecord::Base.transaction do
            agent_bot = AgentBot.create!(account: @account, name: @agent.name, bot_type: :webhook,
                                         outgoing_url: nil)
            AgentBotInbox.create!(inbox: @inbox, agent_bot: agent_bot, account: @account)
            agent_inbox = ::Autonomia::Agents::AgentInbox.create!(
              agent: @agent, inbox: @inbox, account: @account, agent_bot: agent_bot
            )
          end
          Result.new(status: :ok, agent_inbox: agent_inbox)
        end

        def disconnect!
          agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(agent: @agent, inbox: @inbox)
          return Result.new(status: :error, error: :not_connected) if agent_inbox.nil?

          ActiveRecord::Base.transaction do
            release_bot_conversations(agent_inbox.agent_bot_id)
            # Destrói o VÍNCULO primeiro: o after_destroy :cleanup_mirror_bot do AgentInbox remove o
            # AgentBotInbox-espelho + o AgentBot-espelho (outgoing_url NULL) NA ORDEM SEGURA. Destruir
            # o AgentBot antes violava a FK autonomia_agent_inboxes.agent_bot_id (null:false, sem
            # cascade) → ActiveRecord::InvalidForeignKey abortava o disconnect manual. Centraliza a
            # limpeza no callback do model (mesmo caminho de Inbox#destroy / Agent#destroy).
            agent_inbox.destroy!
          end
          Result.new(status: :ok)
        end

        # Libera ao humano qualquer conversa em que o bot ainda esteja no comando: as `pending` e as
        # `open` que ainda têm o espelho como ai_assignee (na caixa do espelho as conversas nascem
        # open com assignee_agent_bot_id = espelho — ver Conversation#set_active_bot_conversation).
        def release_bot_conversations(mirror_bot_id)
          pending = @inbox.conversations.where(status: :pending)
          held_by_mirror = @inbox.conversations.where(status: :open, assignee_agent_bot_id: mirror_bot_id)
          pending.or(held_by_mirror).find_each(&:bot_handoff!)
        end

        def agent_operable?
          @agent.enabled? && @agent.active?
        end

        # Há um AgentBot webhook real (Gabriela) ocupando o inbox? Consulta direta por
        # join (não via has_one :through, que com >1 linha resolveria uma arbitrária e
        # poderia não enxergar o bot webhook).
        def webhook_bot_present?
          AgentBotInbox.joins(:agent_bot)
                       .where(inbox_id: @inbox.id)
                       .where.not(agent_bots: { outgoing_url: [nil, ''] })
                       .exists?
        end

        def already_connected?
          ::Autonomia::Agents::AgentInbox.exists?(inbox_id: @inbox.id)
        end
      end
    end
  end
end
