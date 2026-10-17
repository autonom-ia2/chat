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

        # Agente e depois caixa (#1648): a conferência da caixa (robô de fora, porta já ocupada) roda com a caixa travada.
        # O set_agent_bot da aba "Agente externo" trava a mesma caixa (Autonomia::Agents::CaixaSemAgenteExterno), então
        # um dos dois espera o outro e enxerga o que ele gravou; agent_bot_inboxes não tem índice único por caixa.
        def connect!
          @agent.with_lock do
            travar_caixa!
            connect_locked!
          end
        end

        # A trava da caixa vale até o fim da transação do agente. Trava uma cópia lida do banco, não o @inbox de quem
        # chamou: `@inbox.lock!` o recarregaria (e às associações dele) por baixo de quem chamou.
        def travar_caixa!
          ::Inbox.lock.find(@inbox.id)
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

        # #1366 — trava o AGENTE primeiro (ordem agente → caixa, a mesma do connect!, das Areas e do SoftDelete): se este
        # era o último vínculo, a parada automática relê os vínculos com ele travado. A caixa também (#1648): a saída da
        # porta e um set_agent_bot na mesma caixa não se cruzam.
        def disconnect!
          @agent.with_lock do
            travar_caixa!
            disconnect_locked!
          end
        end

        def disconnect_locked!
          agent_inbox = ::Autonomia::Agents::AgentInbox.kept.find_by(agent: @agent, inbox: @inbox)
          return Result.new(status: :error, error: :not_connected) if agent_inbox.nil?
          return disconnect_area! if agent_inbox.area?

          ActiveRecord::Base.transaction do
            # #1433: as áreas da caixa ficam (a caixa passa a ser só de pessoas); saem só as conversas da porta.
            agent_inbox.release_bot_conversations!
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
