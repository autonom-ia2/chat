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

      # Checks que expõem estado de CONFIGURAÇÃO da conta → só para administrador. Notificações são
      # preferências do próprio usuário → liberadas a qualquer perfil.
      ADMIN_CHECKS = %w[channel routing ai_agent calendar].freeze

      def admin?
        @account_user&.role.to_s == 'administrator'
      end

      # Procura nos melhores fluxos um de diagnóstico (`diagnostic:`) e roda a checagem read-only do
      # estado real da conta.
      #
      # Não há filtro de palavra decidindo se a mensagem "é um relato de problema": quem seleciona é o
      # próprio buscador, trazendo — ou não — um fluxo de diagnóstico para o assunto. Uma lista de
      # sintomas escrita à mão deixaria de fora o sintoma escrito com outras palavras, e o Guia
      # responderia pelo manual sem nunca olhar o estado real.
      def diagnostic_context(agent)
        # Best-effort: se o retrieval falhar por INFRA (#14, RetrievalError), apenas pula o diagnóstico
        # (não derruba a Guia) — o Answerer abaixo trata a mesma falha no caminho gateado (handoff seguro).
        tops = begin
          ::Autonomia::Agents::Retriever.new(agent: agent).retrieve(@message, top_k: 3)
        rescue ::Autonomia::Agents::Retriever::RetrievalError
          []
        end
        entry = tops.find { |t| campo(t.content.to_s, 'diagnostic').present? }
        return nil if entry.nil?

        check = campo(entry.content.to_s, 'diagnostic')
        return nil if check.blank?
        return nil if ADMIN_CHECKS.include?(check) && !admin?

        findings = ::Autonomia::Guide::Diagnostics.run(check, account: @account, user: @user)
        return nil if findings.nil? # checagem falhou → não injeta (não vira falso "tudo certo")

        { check: check, findings: findings }
      rescue StandardError => e
        Rails.logger.warn("[autonomia][guide][chat] diagnostic_context account=#{@account&.id} #{e.class}: #{e.message}")
        nil
      end

      # Qual recurso da plataforma responde a esta pergunta. Quem escolhe é quem
      # entendeu a pergunta — o modelo, a partir do catálogo derivado do roteador.
      #
      # NÃO existe filtro de palavra antes disto, de propósito. Já tentamos duas
      # vezes: um marcador escondido no fluxo do manual, depois uma lista de
      # palavras ("quais", "quantos"). As duas vezes o Guia entendeu a pergunta e
      # mesmo assim não foi buscar o dado, porque a pergunta não estava escrita do
      # jeito que a lista esperava. Quem decide se precisa de dado é quem lê a
      # pergunta; o modelo devolve nulo quando não precisa.
      def leitura_context(_agent)
        escolha = escolher_recurso(consulta.catalogo)
        return nil if escolha.blank?

        conteudo = consulta.ler(escolha[:recurso], escolha[:parametros])
        return nil if conteudo.blank?

        ["Consultei #{escolha[:recurso]} nesta conta e recebi: #{conteudo}"]
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
        route = campo(content, 'nav_target')
        return nil if route.blank? || route == '—'

        { route_name: route, label: titulo(content), highlight: campo(content, 'highlight') }
      end

      # O fluxo do KB é texto de campo por linha, escrito pelo nosso gerador:
      # `nav_target: \`crm_index\``. Ler isso é separar linha e pegar o que vem
      # depois dos dois pontos — não precisa de padrão, e padrão aqui já custou
      # caro: uma rota com parâmetro foi comida por um deles.
      def campo(conteudo, nome)
        linha = conteudo.lines.find { |l| l.strip.downcase.start_with?("#{nome}:") }
        return nil if linha.nil?

        linha.strip.split(':', 2).last.to_s.delete('`').strip.presence
      end

      def titulo(conteudo)
        linha = conteudo.lines.find { |l| l.start_with?('### ') }
        linha.to_s.delete_prefix('### ').strip.presence
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
