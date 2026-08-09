module Crm
  module Ai
    # Single "brain" for AI auto follow-up. Reads the primary conversation
    # transcript (via ContextBuilder, resolved by the CALLER) and decides, in one
    # gate, whether it is worth following up now AND how.
    #
    # Mirrors StageClassifier's contract: the caller resolves the OpenAI
    # credential (CredentialResolver), builds ResponsesClient.new(credential:) and
    # ContextBuilder.new(card:).perform, then passes both in. This service only
    # assembles the prompt + strict JSON schema and parses the response.
    #
    # Two modes (decided by the runner from the messaging window):
    #   :free_form      — inside the 24h window: write a natural PT-BR message_body.
    #   :choose_template — outside the 24h window: pick the BEST approved template
    #                      from +candidates+ (by index) and fill its variables.
    #
    # Single gate: the model decides should_send (vale a pena dar follow agora?) and
    # detects closure/satisfaction (closure_detected) which forces should_send=false.
    # It NEVER decides window/cap/budget — that is the runner's job.
    #
    # Anti-hallucination: the model MUST cite a literal transcript line in
    # open_loop_source; if no real open loop exists it returns should_send=false.
    class FollowUpComposer
      COMPOSE_SCHEMA = {
        name: 'crm_ai_followup',
        schema: {
          type: 'object',
          properties: {
            should_send: {
              type: 'boolean',
              description: 'Vale a pena dar follow agora? false se a conversa estiver encerrada/satisfeita/sem interesse/' \
                           'compra concluída, ou se não houver um loop aberto real.'
            },
            closure_detected: {
              type: 'boolean',
              description: 'true quando a conversa demonstra encerramento/satisfação (ex.: "obrigado por comprar, conte ' \
                           'comigo", "não tenho interesse", compra concluída). Quando true, should_send DEVE ser false.'
            },
            open_loop: {
              type: 'string',
              maxLength: 400,
              description: 'Descrição curta do que ficou em aberto (pergunta sem resposta, info prometida, decisão pendente).'
            },
            open_loop_source: {
              type: 'string',
              maxLength: 400,
              description: 'Trecho LITERAL de uma mensagem da conversa que comprova o loop aberto. Não invente.'
            },
            message_body: {
              type: 'string',
              maxLength: 700,
              description: 'Mensagem de follow-up natural em PT-BR. Usada APENAS no modo free_form (dentro da janela 24h).'
            },
            chosen_template: {
              type: 'object',
              description: 'Template escolhido no modo choose_template (fora da janela 24h). Objeto zerado no modo free_form.',
              properties: {
                index: {
                  type: 'integer',
                  description: 'Índice (base 0) do candidato escolhido na lista candidates. -1 se nenhum for adequado.'
                },
                kind: { type: 'string', enum: %w[native api] },
                name: { type: 'string' },
                id: { type: %w[integer null] },
                language: { type: %w[string null] }
              },
              required: %w[index kind name id language],
              additionalProperties: false
            },
            template_variables: {
              type: 'array',
              description: 'Pares posição/valor para preencher o template escolhido (modo choose_template). ' \
                           'Lista vazia no free_form ou quando o template não usa variáveis. ' \
                           'A Responses API em modo strict não aceita objeto de chaves dinâmicas, por isso é uma lista.',
              items: {
                type: 'object',
                properties: {
                  position: { type: 'string', description: 'Número posicional do placeholder, ex.: "1", "2".' },
                  value: { type: 'string', description: 'Valor para preencher o placeholder.' }
                },
                required: %w[position value],
                additionalProperties: false
              }
            },
            next_action_owner: {
              type: 'string',
              enum: %w[cliente empresa terceiro],
              description: 'De quem é a PRÓXIMA ação combinada na conversa. "empresa" na dúvida.'
            },
            message_kind: {
              type: 'string',
              enum: %w[cobranca aviso_andamento],
              description: 'cobranca = retoma pedindo algo ao cliente. aviso_andamento = informa que seguimos ' \
                           'aguardando, sem pedir nada.'
            },
            tone: { type: 'string', enum: %w[friendly neutral helpful] },
            confidence: { type: 'number', minimum: 0, maximum: 1 }
          },
          required: %w[should_send closure_detected open_loop open_loop_source message_body chosen_template
                       template_variables next_action_owner message_kind tone confidence],
          additionalProperties: false
        }
      }.freeze

      # purpose: :followup (padrão — retomar conversa parada, gate de "loop aberto") OU :callback
      # (cliente PEDIU um retorno numa data; a "tarefa" é retomar o contato como combinado, NÃO caçar
      # silêncio). callback_context: { requested_at_text:, requested_at: } usado só no :callback.
      # cadence: { interval_hours:, touch:, max_touches: } — a régua de tempo da cadência. A regra de
      # PRAZO manda comparar a idade da última fala do cliente com "o intervalo entre os toques", e
      # esse número nunca era enviado: o modelo tinha que adivinhar se o prazo venceu. Vazio no modo
      # callback, que não tem cadência.
      def initialize(card:, client:, context:, mode: :free_form, candidates: [], tone_instructions: '',
                     purpose: :followup, callback_context: {}, cadence: {},
                     model: Config::MODEL_FOLLOWUP, reasoning_effort: Config::FOLLOWUP_REASONING_EFFORT)
        @card = card
        @client = client
        @context = context
        @mode = mode.to_sym
        @candidates = Array(candidates)
        @cadence = (cadence || {}).to_h
        @tone_instructions = tone_instructions.to_s.strip
        @purpose = purpose.to_sym
        @callback_context = (callback_context || {}).to_h
        @model = model
        @reasoning_effort = reasoning_effort
      end

      def perform
        response = @client.create(
          model: @model,
          instructions: instructions,
          input: user_input,
          schema: COMPOSE_SCHEMA,
          reasoning_effort: @reasoning_effort
        )

        parsed = JSON.parse(response[:text])
        # The strict schema returns template_variables as a [{position,value}] list
        # (open-ended-key objects are not allowed in strict mode). Collapse it back
        # to the {"1" => "João"} hash the runner/MessageSender expect.
        parsed['template_variables'] = normalize_template_variables(parsed['template_variables'])

        parsed.with_indifferent_access.merge(
          model_used: @model,
          usage: response[:usage],
          response_id: response[:response_id]
        )
      end

      private

      def normalize_template_variables(raw)
        return raw if raw.is_a?(Hash)
        return {} unless raw.is_a?(Array)

        raw.each_with_object({}) do |pair, acc|
          position = pair['position'].to_s.strip
          acc[position] = pair['value'].to_s if position.present?
        end
      end

      def choose_template_mode?
        @mode == :choose_template
      end

      def instructions
        return callback_instructions if @purpose == :callback

        <<~PROMPT.strip
          Você é o cérebro de follow-up em português do Brasil para retomar conversas de vendas/atendimento que ficaram paradas, "de onde a conversa parou".
          Responda apenas com JSON válido no schema solicitado.

          #{turn_owner_rules}

          PORTÃO ÚNICO — decida should_send (vale a pena dar follow agora?):
          - Encontre UM único loop aberto real na conversa: o cliente perguntou/pediu e não foi respondido; prometemos algo e não enviamos; havia uma decisão pendente e o cliente sumiu depois que perguntamos.
          - #{ContextBuilder::ROLES_LEGEND} "last_message_role" repete o papel da última mensagem. Quem falou por último NÃO define, sozinho, de quem é a pendência — leia a conversa.
          - Use "temporal.now_local" (data e hora de agora, no fuso do contato) junto com o "created_at" de cada mensagem para saber há quanto tempo cada coisa aconteceu.
          - Use "conversation_state": "status" da conversa, "assigned_to_human" (há uma pessoa do time responsável) e "last_human_agent_at" (quando um humano falou por último).
          - DETECTE ENCERRAMENTO/SATISFAÇÃO: se a conversa mostra que já foi resolvida, o cliente agradeceu/comprou, disse que não tem interesse, ou pediu para não ser mais contatado (ex.: "obrigado por comprar, conte comigo", "não tenho interesse", compra concluída) → defina closure_detected=true e should_send=false.
          - Se não houver loop aberto real citável, defina should_send=false.

          ANTI-ALUCINAÇÃO (regra dura):
          - O loop aberto DEVE estar comprovado por um trecho LITERAL copiado de uma mensagem da conversa em "open_loop_source". Copie a frase inteira, não um pedaço solto: trecho curto ("ok", "pode mandar") não prova nada e é recusado.
          - Nunca invente fatos, nomes, valores, prazos ou contexto que não estejam na conversa.
          - Se should_send=false, deixe message_body curto/genérico e confidence baixa.

          #{mode_instructions}

          "tone" reflete o tom usado (friendly/neutral/helpful). "confidence" (0.0 a 1.0) reflete o quão claro é o loop aberto e o quão adequado é o follow agora.
          #{tone_instructions_line}
        PROMPT
      end

      # Enquadramento de CALLBACK: o cliente PEDIU um retorno numa data/hora — a tarefa é RETOMAR o
      # contato como combinado, não caçar silêncio. Mesmo schema; o "loop aberto" aqui É o pedido de
      # retorno (open_loop_source = a frase LITERAL onde o cliente pediu). should_send=false +
      # closure_detected=true SOMENTE se a conversa mostrar que o cliente DESISTIU/CANCELOU ou o assunto
      # já foi resolvido depois ("não precisa mais", "já resolvi", "comprei em outro lugar").
      def callback_instructions
        req = @callback_context['requested_at_text'].to_s.strip
        <<~PROMPT.strip
          Você é o cérebro de RETORNO AGENDADO em português do Brasil. O cliente PEDIU para ser contatado/retornado
          numa data/hora específica#{req.present? ? " (pedido original: \"#{req}\")" : ''}. Sua tarefa é RETOMAR o contato
          de forma natural e cordial, como combinado — NÃO é caçar silêncio nem inventar urgência.
          Responda apenas com JSON válido no schema solicitado.

          PORTÃO: por padrão should_send=true (é um retorno que o PRÓPRIO cliente pediu). Em "open_loop" descreva
          "retorno solicitado pelo cliente" e em "open_loop_source" copie o trecho LITERAL onde ele pediu o retorno.
          EXCEÇÃO — defina closure_detected=true e should_send=false SOMENTE se, DEPOIS do pedido, a conversa mostrar
          que o cliente desistiu/cancelou, já resolveu, comprou em outro lugar, ou pediu para não ser mais contatado.

          ANTI-ALUCINAÇÃO (regra dura): nunca invente fatos, nomes, valores ou prazos fora da conversa. A mensagem deve
          ser uma retomada curta e cordial (ex.: "Oi! Como combinado, estou retomando nosso contato. Posso te ajudar com…").

          #{mode_instructions}

          Este modo é um retorno que o cliente pediu, não um follow-up por silêncio: preencha
          next_action_owner="empresa" (o retorno é nosso) e message_kind="cobranca". O CallbackRunner não lê
          esses dois campos — eles existem só porque o schema é compartilhado com o follow-up.

          "tone" friendly/neutral/helpful. "confidence" (0.0 a 1.0) reflete o quão adequado é retomar agora.
          #{tone_instructions_line}
        PROMPT
      end

      # "Tem assunto em aberto?" não basta: no caso que originou esta regra o assunto estava aberto e
      # a pendência era NOSSA — o cliente tinha respondido "vou aguardar". Por isso a vez vem antes do
      # portão, e a dúvida cai para "empresa": errar para o lado de avisar é bem menos pior que cobrar
      # o cliente por algo que ele não deve.
      def turn_owner_rules
        <<~RULES.strip
          PRIMEIRA PERGUNTA — de quem é a vez (next_action_owner):
          - "cliente": nós perguntamos ou pedimos algo e ele não respondeu.
          - "empresa": nós prometemos algo e não entregamos, ou o cliente perguntou e não foi respondido.
          - "terceiro": o que falta depende de alguém fora da conversa (seguradora, banco, fornecedor) e nós já acionamos.
          - Confirmação passiva do cliente ("ok", "beleza", "combinado", "vou aguardar", "fico no aguardo") logo depois de uma promessa nossa significa "empresa". Isso NÃO é o cliente sumindo.
          - Na dúvida, escolha "empresa". Nunca cobre o cliente por algo que pode ser nosso.

          SEGUNDA PERGUNTA — o que escrever (message_kind):
          - Se a vez é do "cliente": message_kind="cobranca". Escreva o follow-up retomando o ponto que ficou em aberto.
          - Se a vez é da "empresa" ou de "terceiro": NÃO cobre e NÃO peça nada.
            · Prazo que prometemos ainda não venceu → should_send=false.
            · Prazo já venceu → message_kind="aviso_andamento" e escreva um aviso curto de andamento, sem novidade inventada e sem pedido (ex.: "ainda estou com a seguradora; assim que retornar eu te trago o orçamento").
          - PRAZO: se a conversa disser o prazo ("te retorno hoje", "até amanhã", "na segunda"), use o que foi dito. Se não disser, considere vencido quando a última mensagem do cliente já estiver mais antiga que o intervalo entre os toques. O intervalo vem em "cadence.interval_hours" (horas); "cadence.touch" e "cadence.max_touches" dizem qual toque é este e quantos existem no total.
        RULES
      end

      def mode_instructions
        if choose_template_mode?
          <<~MODE.strip
            MODO choose_template (a conversa está FORA da janela de 24h):
            - Você recebe candidates: uma lista de templates APROVADOS do inbox, cada um com index, kind, name, language, body, variables e category.
            - "category" é "utility", "marketing" ou nulo (inbox sem categoria da Meta). Quando mais de um candidato servir igualmente bem, prefira "utility": template "marketing" tem teto de 1 envio por contato a cada 24h, e escolher marketing sem necessidade faz o toque ser adiado.
            - Se should_send=true, escolha o MELHOR candidato para reabrir o loop e preencha chosen_template.index com o índice (base 0) dele. Copie também kind/name/id/language do candidato escolhido (o runner usa o index como autoridade).
            - Preencha template_variables com os valores posicionais ("1","2",...) que o body do template usa (ex.: "1" = primeiro nome do contato, "2" = assunto curto do loop). Apenas valores reais, nunca texto livre de template.
            - Se NENHUM candidato for adequado ao loop aberto, defina should_send=false e chosen_template.index=-1.
            - NÃO escreva message_body neste modo (deixe vazio).
          MODE
        else
          <<~MODE.strip
            MODO free_form (a conversa está DENTRO da janela de 24h):
            - Se should_send=true, escreva "message_body" para reabrir a conversa: tom de quem quer ajudar uma pessoa, NÃO vendedor; sem falsa urgência; sem pedir desculpas em excesso; no máximo 2-3 linhas curtas de chat com 1 CTA suave; personalize APENAS com fatos reais (use o primeiro nome se aparecer); retome explicitamente o ponto que ficou em aberto.
            - chosen_template NÃO é usado neste modo: devolva um objeto zerado (index=-1, kind="native", name="", id=null, language=null) e template_variables vazio.
          MODE
        end
      end

      def tone_instructions_line
        return '' if @tone_instructions.blank?

        "INSTRUÇÕES DE TOM/MARCA (siga rigorosamente): #{@tone_instructions}"
      end

      def user_input
        payload = {
          mode: @mode,
          card: {
            id: @card.id,
            title: @card.title,
            current_stage_name: @context[:current_stage]&.dig(:name)
          },
          conversation_summary: @context[:summary],
          conversation_state: @context[:conversation_state],
          temporal: @context[:temporal],
          recent_messages: @context[:recent_messages],
          last_message_role: last_message_role,
          tone_instructions: @tone_instructions
        }
        payload[:cadence] = @cadence if @cadence.present?
        payload[:candidates] = candidates_for_input if choose_template_mode?
        payload.to_json
      end

      def candidates_for_input
        @candidates.each_with_index.map do |candidate, index|
          {
            index: index,
            kind: candidate[:kind],
            name: candidate[:name],
            language: candidate[:language],
            body: candidate[:body],
            variables: candidate[:variables],
            category: candidate[:category]
          }
        end
      end

      # Role of the most recent transcript message: tells the model the stall type
      # (we-asked vs they-asked). ContextBuilder already labels roles customer/agent.
      def last_message_role
        Array(@context[:recent_messages]).last&.dig(:role)
      end
    end
  end
end
