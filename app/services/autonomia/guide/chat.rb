module Autonomia
  module Guide
    # Chat do Guia da Plataforma: ancorado nos 163 fluxos (RAG), ciente de perfil, com sugestão de
    # navegação, leitura do que a conta tem e proposta de ação. Reusa o motor Autonomia (Answerer →
    # Retriever → ResponsesClient → portão de confiança). Best-effort: nunca levanta.
    #
    # Nada é EXECUTADO aqui: esta classe monta a proposta; quem executa é o controller, e só depois
    # da confirmação na tela.
    class Chat
      Result = Struct.new(:text, :navigation, :grounded, :confidence, :available, :escalate, :acao,
                          :retido, keyword_init: true)

      # Quantas mensagens da conversa seguem junto. Eram 12 — seis idas e voltas,
      # curto demais para quem está configurando a conta e vai perguntando uma
      # coisa atrás da outra: o Guia perdia o fio no meio do assunto. A pedido do
      # Rodrigo, 20. É teto de mensagens, não de caracteres; cada uma ainda entra
      # inteira no contexto, então subir muito acima disto custa token em toda
      # pergunta.
      MAX_HISTORY = 20
      NAV_MIN_CONFIDENCE = 0.45

      # Quantas idas ao modelo podem sair COM ferramenta (#568). Dez, por decisão
      # do Rodrigo em 21/09/2026 — o número que ele já operava no n8n.
      #
      # Só é possível porque esta classe roda num JOB (`Autonomia::Guide::ChatJob`,
      # #572), e não na requisição. Na requisição o `rack-timeout` de produção
      # mata tudo aos 15 segundos, e cada ida ao modelo leva de 3 a 5: medido em
      # 21/09/2026, duas leituras já davam erro 500.
      #
      # Se alguém voltar a chamar isto de dentro de uma requisição, este número
      # tem que cair para 1 — senão o Guia volta a morrer em pergunta aberta.
      MAX_RODADAS = 10

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

        result = ::Autonomia::Agents::Answerer.new(
          agent: agent, query: role_scoped_query(diagnostics), history: sanitized_history,
          # A busca tem que ser feita pela PERGUNTA, não pela query montada. O catálogo de leitura
          # tem 7.589 caracteres e vem ANTES da pergunta; o Retriever corta preservando o começo,
          # então o embedding sairia do catálogo e a pergunta ficaria de fora. Vinham fluxos
          # irrelevantes: tela errada no botão e confiança baixa, que o portão transforma em
          # "o guia está indisponível".
          retrieval_query: @message,
          allow_web_search: false, # KB-only: o Guia responde só da nossa base, nunca de fonte externa
          # #568 — QUEM está perguntando. É com a permissão dela que as ferramentas
          # leem a conta e preparam a mudança; não existe permissão "do agente".
          operador: contexto,
          # Ler, olhar o que voltou e ler de novo, até dez vezes — e sempre
          # dentro do orçamento de tempo do cliente.
          max_rodadas: MAX_RODADAS
        ).answer

        # A proposta nasce DENTRO da ferramenta, durante a redação — por isso é
        # lida depois. É o que acabou com o texto discordando do botão: quem
        # escreve a resposta é quem propôs a ação.
        acao = contexto.proposta

        # #13 — NÃO servir `raw_reply` (texto PRÉ-portão) ao usuário: quando o portão retém a resposta
        # (baixa confiança/ungrounded), cai no fallback configurado da Guia ou em "indisponível" — nunca
        # no texto ungrounded do modelo. raw_reply fica restrito à revisão humana (copiloto/sugestão).
        text = result.reply.to_s.strip
        # Texto vazio aqui NÃO significa que o Guia está fora do ar: significa que o portão de
        # confiança reteve a resposta. O agente é semeado com `fallback_message: nil`, então o
        # portão devolve vazio, e a tela mostrava "o guia está indisponível" — a mesma frase para
        # a OpenAI fora, para o banco de vetores fora, e para "li o seu dado certinho e fui
        # censurado por não estar ancorado num fluxo do manual". Separar os dois é o mínimo para
        # alguém conseguir diagnosticar, e para a pessoa não achar que o produto caiu.
        return retido if text.blank?

        Result.new(text: text, navigation: navegacao(result), acao: acao,
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
      def role_scoped_query(diagnostics = nil)
        role = @account_user&.role.presence || 'agent'
        ctx = "[CONTEXTO INTERNO (não é fala do usuário). Perfil do usuário: #{role}. " \
              "Tela atual: #{@route_context.presence || 'não informada'}. Adapte a resposta a este " \
              "perfil e oriente apenas o que ele pode fazer; se a ação for de administrador e o " \
              "perfil não for administrator, explique que é feito pelo administrador da conta.]"
        "#{ctx}#{catalogos}#{diagnostic_block(diagnostics)}\n\n#{@message}"
      end

      # O MAPA do que as ferramentas alcançam, para o modelo saber o que pedir.
      # Sai do roteador: nasce completo e cresce junto com a plataforma.
      #
      # Só o de LEITURA entra aqui, e a medida é o motivo: o catálogo de leitura
      # tem 7.589 caracteres e o de escrita, 16.245. Os dois somados seriam
      # quase 24 mil em TODA pergunta — um terço do bloco que, medido em
      # 21/09/2026, fez o modelo perder a pergunta de vista. O nome da rota de
      # escrita ele deduz da de leitura (o verbo é um dos quatro), e quando
      # errar a ferramenta responde com as ações daquele recurso.
      def catalogos
        "\n\n[RECURSOS QUE VOCÊ PODE LER com `ler_da_conta` (dado, não fala do usuário): " \
          "#{contexto.consulta.catalogo.join(', ')}]"
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

      def contexto
        @contexto ||= ::Autonomia::Guide::Contexto.new(account: @account, user: @user,
                                                       account_user: @account_user)
      end

      def sanitized_history
        @history.last(MAX_HISTORY).filter_map do |h|
          role = h[:role].to_s
          content = h[:content].to_s.strip
          next if content.blank? || !%w[user assistant].include?(role)

          { role: role, content: content }
        end
      end

      # A tela do botão (#590). Vale primeiro a que o modelo escolheu com `mostrar_tela`: é a única
      # que sabe QUAL caixa, conversa ou agente, porque ele leu a conta. Quando ele não escolhe
      # nenhuma, fica a do fluxo do manual — que leva à tela geral, como antes.
      def navegacao(result)
        return nil if result.handoff.to_h[:should] == true

        contexto.tela || resolve_navigation(result)
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

      # O gerador escreve cada campo como ITEM DE LISTA:
      #   - nav_target: `crm_kanban_index`
      # O traço faz parte do formato (scripts/guide-map/build.mjs) e é cobrado
      # pelo teste do registro no front. A primeira versão deste método ancorava
      # em "nav_target:" no começo da linha e devolvia nil nos 163 blocos — o
      # botão de navegação, o destaque e o diagnóstico morreram juntos, calados.
      # O comentário que eu escrevi virou a especificação no lugar do arquivo.
      MARCADOR_DE_LISTA = '- '.freeze

      def campo(conteudo, nome)
        prefixo = "#{nome}:"
        linha = conteudo.lines
                        .map { |l| l.strip.delete_prefix(MARCADOR_DE_LISTA).lstrip }
                        .find { |l| l.downcase.start_with?(prefixo) }
        return nil if linha.nil?

        # Fatia por posição, não por separador: valor que contenha ':' sobrevive.
        linha[prefixo.length..].to_s.delete('`').strip.presence
      end

      def titulo(conteudo)
        linha = conteudo.lines.find { |l| l.start_with?('### ') }
        linha.to_s.delete_prefix('### ').strip.presence
      end

      def unavailable
        Result.new(text: nil, navigation: nil, grounded: false, confidence: nil,
                   available: false, escalate: false)
      end

      # O Guia está no ar e entendeu; só não está seguro o bastante para afirmar.
      # A tela traduz isso numa frase própria, com a oferta de suporte — em vez
      # de dizer que o produto caiu.
      def retido
        Result.new(text: nil, navigation: nil, grounded: false, confidence: nil,
                   available: true, escalate: true, retido: true)
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
