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
      #             pending ao humano via bot_handoff!. Era o último vínculo: o agente para (AgentInbox, #1366).
      #
      # #1366 — `ativar: true` é o "Começar a atender neste canal": aceita o agente parado ou em rascunho e o liga
      # (active + enabled) na MESMA transação do vínculo. Ativar antes, sozinho, não dá mais: agente sem onde trabalhar
      # não fica atendendo (Agent#tem_onde_trabalhar?). Sem `ativar`, a regra de sempre: só conecta agente que atende.
      class InboxConnector
        Result = Struct.new(:status, :error, :agent_inbox, keyword_init: true) do
          def success?
            status == :ok
          end
        end

        def initialize(agent:, inbox:, ativar: false)
          @agent = agent
          @inbox = inbox
          @account = agent.account
          @ativar = ativar
        end

        def perform(connect:)
          connect ? connect! : disconnect!
        end

        private

        def connect!
          @agent.with_lock { connect_locked! }
        end

        def connect_locked!
          recusa = recusa_de_conexao
          return Result.new(status: :error, error: recusa) if recusa

          Result.new(status: :ok, agent_inbox: criar_vinculo!)
        end

        def recusa_de_conexao
          # V2.1 — agente INTERNO (copiloto da equipe) NUNCA atende cliente: bloqueia o vínculo de caixa
          # (não cria AgentBot/AgentBotInbox/AgentInbox). Autoridade no backend; a UI esconde como 2ª defesa.
          return :agent_internal_not_connectable if @agent.actuation_internal?
          return :agent_not_active unless agent_operable? || @ativar
          return :inbox_has_webhook_bot if webhook_bot_present?

          :inbox_already_connected if already_connected?
        end

        def criar_vinculo!
          ActiveRecord::Base.transaction do
            agent_bot = AgentBot.create!(account: @account, name: @agent.name, bot_type: :webhook,
                                         outgoing_url: nil)
            AgentBotInbox.create!(inbox: @inbox, agent_bot: agent_bot, account: @account)
            agent_inbox = ::Autonomia::Agents::AgentInbox.create!(
              agent: @agent, inbox: @inbox, account: @account, agent_bot: agent_bot
            )
            # Depois do vínculo: a validação de atender já o enxerga. Recusada, a transação desfaz o vínculo.
            @agent.update!(status: :active, enabled: true) if @ativar && !@agent.operating?
            agent_inbox
          end
        end

        def disconnect!
          agent_inbox = ::Autonomia::Agents::AgentInbox.kept.find_by(agent: @agent, inbox: @inbox)
          return Result.new(status: :error, error: :not_connected) if agent_inbox.nil?
          return disconnect_area! if agent_inbox.area?

          ActiveRecord::Base.transaction do
            # #1433: área só existe em caixa com porta ativa. Trava a caixa (como o Areas.vincular!) e solta as áreas
            # antes das conversas da porta; as conversas delas vão direto para a equipe humana.
            @inbox.lock!
            agent_inbox.sair_da_caixa!
            # Destrói o VÍNCULO primeiro: o after_destroy :cleanup_mirror_bot do AgentInbox remove o
            # AgentBotInbox-espelho + o AgentBot-espelho (outgoing_url NULL) NA ORDEM SEGURA. Destruir
            # o AgentBot antes violava a FK autonomia_agent_inboxes.agent_bot_id (null:false, sem
            # cascade) → ActiveRecord::InvalidForeignKey abortava o disconnect manual. Centraliza a
            # limpeza no callback do model (mesmo caminho de Inbox#destroy / Agent#destroy).
            agent_inbox.destroy!
          end
          Result.new(status: :ok)
        end

        # Vínculo de área (#1433) sai pelo mesmo caminho da tela do CRM: arquiva e guarda o espelho.
        def disconnect_area!
          ::Autonomia::Agents::Areas.desvincular!(agent: @agent, inbox: @inbox)
          Result.new(status: :ok)
        end

        def agent_operable?
          @agent.operating?
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
          ::Autonomia::Agents::AgentInbox.kept.porta.exists?(inbox_id: @inbox.id)
        end
      end
    end
  end
end
