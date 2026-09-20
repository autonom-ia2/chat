module Autonomia
  module Guide
    # Chat do Guia da Plataforma: READ-ONLY, ancorado nos ~81 fluxos (RAG), CIENTE DE PERFIL e com
    # sugestão de navegação (nav_target). Nunca opera nada. Reusa o motor Autonomia (Answerer →
    # Retriever → ResponsesClient → portão de confiança). Best-effort: nunca levanta (available:false).
    class Chat
      Result = Struct.new(:text, :navigation, :grounded, :confidence, :available, :escalate, :acao,
                          keyword_init: true)

      MAX_HISTORY = 12
      NAV_MIN_CONFIDENCE = 0.45

      def initialize(account:, user:, message:, history: [], route_context: nil)
        @account = account
        @user = user
        @account_user = account&.account_users&.find_by(user_id: user&.id)
        @message = message.to_s
        @history = Array(history)
        @route_context = route_context.to_s
      end

      def perform
        return unavailable if @message.strip.blank?

        # AUTO-ON async: o Guia nasce sozinho em conta elegível, mas a preparação da KB roda em job.
        # A rota de chat nunca gera embeddings no request do usuário, evitando rack-timeout.
        agent = ::Autonomia::Guide::Seed.ready_agent_for(@account)
        if agent.nil?
          return preparing if ::Autonomia::Guide::Seed.ensure_async_for(@account)

          return unavailable
        end

        # V3: se o melhor fluxo recuperado é de diagnóstico (campo `diagnostic:`), lê o ESTADO REAL da
        # conta (read-only) e injeta como contexto — o Answerer explica com base no estado, não inventa.
        diagnostics = diagnostic_context(agent)
        # #533 — pergunta sobre o que a conta TEM ("quais funis?", "quantas
        # campanhas?") é respondida com os dados, não com o manual.
        leituras = leitura_context(agent)

        result = ::Autonomia::Agents::Answerer.new(
          agent: agent, query: role_scoped_query(diagnostics, leituras), history: sanitized_history,
          allow_web_search: false # KB-only: o Guia responde só da nossa base, nunca de fonte externa
        ).answer

        # #13 — NÃO servir `raw_reply` (texto PRÉ-portão) ao usuário: quando o portão retém a resposta
        # (baixa confiança/ungrounded), cai no fallback configurado da Guia ou em "indisponível" — nunca
        # no texto ungrounded do modelo. raw_reply fica restrito à revisão humana (copiloto/sugestão).
        text = result.reply.to_s.strip
        return unavailable if text.blank?

        Result.new(text: text, navigation: resolve_navigation(result), acao: acao_proposta,
                   grounded: result.answered_from_knowledge == true,
                   confidence: result.confidence,
                   available: true, escalate: result.handoff.to_h[:should] == true)
      rescue StandardError => e
        Rails.logger.error("[autonomia][guide][chat] account=#{@account&.id} #{e.class}: #{e.message}")
        unavailable
      end

      private

      # Injeta o PERFIL e a TELA ATUAL como CONTEXTO (dado, não fala), para a instrução adaptar a
      # resposta e só orientar o que o perfil pode fazer. O modelo nunca confia nisso para autorizar
      # — é só para a redação; o backend real (endpoints de domínio) é que aplica Pundit.
      def role_scoped_query(diagnostics = nil, leituras = nil)
        role = @account_user&.role.presence || 'agent'
        ctx = "[CONTEXTO INTERNO (não é fala do usuário). Perfil do usuário: #{role}. " \
              "Tela atual: #{@route_context.presence || 'não informada'}. Adapte a resposta a este " \
              "perfil e oriente apenas o que ele pode fazer; se a ação for de administrador e o " \
              "perfil não for administrator, explique que é feito pelo administrador da conta.]"
        "#{ctx}#{diagnostic_block(diagnostics)}#{leitura_block(leituras)}\n\n#{@message}"
      end

      # O que a conta TEM, lido com a permissão de quem perguntou. Entra como dado,
      # nunca como instrução — os nomes vêm limpos de Leituras#safe.
      def leitura_block(leituras)
        return '' if leituras.blank?

        items = leituras.map { |linha| "- #{linha}" }.join("\n")
        "\n\n[O QUE A CONTA TEM (leitura só-leitura, já filtrada pela permissão de quem perguntou — " \
          "responda com base EXATAMENTE nestes itens; não invente nem complete a lista):\n#{items}]"
      end

      # Bloco de ESTADO REAL (dado, não fala). O modelo deve responder baseado nestes achados de leitura.
      def diagnostic_block(diagnostics)
        return '' if diagnostics.nil?

        if diagnostics[:findings].present?
          items = diagnostics[:findings].map { |f| "- #{f}" }.join("\n")
          "\n\n[ESTADO REAL DA CONTA (diagnóstico só-leitura — explique o usuário com base EXATAMENTE " \
            "nestes achados e oriente o conserto; não invente outros problemas):\n#{items}]"
        else
          "\n\n[ESTADO REAL DA CONTA (diagnóstico só-leitura): nenhum problema detectado nesta área " \
            "para esta conta agora. Diga que está tudo certo por aqui e, se o sintoma persistir, peça " \
            "mais detalhes ou oriente abrir um chamado.]"
        end
      end

      # Sinais de que a mensagem é um RELATO DE PROBLEMA (e não um "como faço"). Só nesse caso vale ler o
      # estado real — assim "Como ativo as notificações?" (how-to) nunca dispara diagnóstico, mas
      # "Por que não recebo notificações?" dispara. Evita misturar diagnóstico com instrução.
      def diagnostic_intent?
        m = @message.to_s.downcase
        return true if m.match?(/\b(por ?que|porqu[eê]|pq)\b/)
        return true if m.match?(/diagn[óo]stic/)
        return true if m.match?(/\b(parou|caiu|desconect\w*|sumiu|trav(ou|ando)|deixou de|n[ãa]o vai|com (erro|problema|falha))\b/)
        # "não (estou/está/consigo) ... <verbo de falha>" — pega "não recebo", "não estou recebendo",
        # "não consigo agendar", "não está conectando" etc., sem casar com how-to ("como ...", sem "não").
        return true if m.match?(/n[ãa]o\s+(estou\s+|est[áa]\s+|consigo\s+|vou\s+)?\w*(funcion|conect|receb|aparec|atribu|cheg|respond|sincroniz|abr|carreg|envi|entreg|agend)/)

        false
      end

      # Checks que expõem estado de CONFIGURAÇÃO da conta → só para administrador. Notificações são
      # preferências do próprio usuário → liberadas a qualquer perfil.
      ADMIN_CHECKS = %w[channel routing ai_agent calendar].freeze

      def admin?
        @account_user&.role.to_s == 'administrator'
      end

      # Quando a mensagem é um relato de problema, procura nos melhores fluxos um de diagnóstico
      # (`diagnostic:`) e roda a checagem read-only do estado real da conta.
      def diagnostic_context(agent)
        return nil unless diagnostic_intent?

        # Best-effort: se o retrieval falhar por INFRA (#14, RetrievalError), apenas pula o diagnóstico
        # (não derruba a Guia) — o Answerer abaixo trata a mesma falha no caminho gateado (handoff seguro).
        tops = begin
          ::Autonomia::Agents::Retriever.new(agent: agent).retrieve(@message, top_k: 3)
        rescue ::Autonomia::Agents::Retriever::RetrievalError
          []
        end
        entry = tops.find { |t| t.content.to_s.match?(/diagnostic:/i) }
        return nil if entry.nil?

        check = entry.content.to_s[/diagnostic:\s*`?([a-z_]+)`?/i, 1]
        return nil if check.blank?
        return nil if ADMIN_CHECKS.include?(check) && !admin?

        findings = ::Autonomia::Guide::Diagnostics.run(check, account: @account, user: @user)
        return nil if findings.nil? # checagem falhou → não injeta (não vira falso "tudo certo")

        { check: check, findings: findings }
      rescue StandardError => e
        Rails.logger.warn("[autonomia][guide][chat] diagnostic_context account=#{@account&.id} #{e.class}: #{e.message}")
        nil
      end

      # Pergunta sobre o ESTADO da conta, não sobre como fazer algo: "quais funis
      # eu tenho?", "quantas campanhas estão ativas?". Só nesse caso vale ler.
      def leitura_intent?
        m = @message.to_s.downcase
        m.match?(/\b(quais|quantos|quantas|qual|tenho|temos|est[ãa]o|listar?|me mostra)\b/)
      end

      # Qual recurso da plataforma responde a esta pergunta. Quem escolhe é quem
      # entendeu a pergunta — o modelo, a partir do catálogo derivado do roteador.
      #
      # Antes isso dependia de um marcador escondido no fluxo do manual, e o Guia
      # entendia a pergunta mas não ia buscar o dado porque o buscador trouxe
      # outro fluxo. Foi o que fez "quantas caixas eu tenho" falhar em produção.
      def leitura_context(_agent)
        return nil unless leitura_intent?

        recurso = escolher_recurso(consulta.catalogo)
        return nil if recurso.blank?

        conteudo = consulta.ler(recurso)
        return nil if conteudo.blank?

        ["Consultei #{recurso} nesta conta e recebi: #{conteudo}"]
      rescue StandardError => e
        Rails.logger.warn("[autonomia][guide][chat] leitura_context account=#{@account&.id} #{e.class}: #{e.message}")
        nil
      end

      # O pedido de FAZER vira proposta: ação, valores e o texto que a pessoa lê
      # antes de confirmar. Nada é executado aqui.
      def acao_proposta
        escolha = ::Autonomia::Guide::EscolhaDaAcao.new(
          account: @account, user: @user, account_user: @account_user
        ).para(@message)
        return nil if escolha.blank?

        acoes = ::Autonomia::Guide::Acoes.new(account: @account, user: @user, account_user: @account_user)
        { nome: escolha[:acao], dados: escolha[:dados], descricao: acoes.descrever(escolha[:acao], escolha[:dados]) }
      rescue ::Autonomia::Guide::Acoes::Recusada, StandardError => e
        Rails.logger.warn("[autonomia][guide][chat] acao_proposta account=#{@account&.id} #{e.class}")
        nil
      end

      def consulta
        @consulta ||= ::Autonomia::Guide::Consulta.new(account: @account, user: @user,
                                                       account_user: @account_user)
      end

      def escolher_recurso(catalogo)
        ::Autonomia::Guide::EscolhaDaConsulta.new(account: @account, catalogo: catalogo).para(@message)
      end

      def sanitized_history
        @history.last(MAX_HISTORY).filter_map do |h|
          role = h[:role].to_s
          content = h[:content].to_s.strip
          next if content.blank? || !%w[user assistant].include?(role)

          { role: role, content: content }
        end
      end

      # Sugestão de navegação extraída do MELHOR fluxo recuperado (campo nav_target do KB). Só sugere
      # quando ancorado + confiante + sem escala. A AUTORIDADE final de "pode navegar" é o FE (valida
      # route name no registry + permissão da rota). Aqui é só candidato.
      def resolve_navigation(result)
        return nil if result.handoff.to_h[:should] == true
        return nil if result.confidence.to_f < NAV_MIN_CONFIDENCE

        top = Array(result.used_knowledge).first
        return nil if top.nil?

        content = top[:content].to_s
        route = content[/nav_target:\s*`?([a-z0-9_]+)`?/i, 1]
        return nil if route.blank? || route == '—'

        label = content[/^###\s*(.+)$/, 1].to_s.strip
        highlight = content[/highlight:\s*`?([a-z0-9_-]+)`?/i, 1]
        { route_name: route, label: label.presence, highlight: highlight.presence }
      end

      def unavailable
        Result.new(text: nil, navigation: nil, grounded: false, confidence: nil,
                   available: false, escalate: false)
      end

      def preparing
        Result.new(
          text: 'Estou preparando o Guia da Plataforma para esta conta. Tente novamente em alguns instantes.',
          navigation: nil, grounded: false, confidence: nil, available: true, escalate: false
        )
      end
    end
  end
end
