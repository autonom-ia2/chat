module Crm
  module Ai
    class StageClassifier # rubocop:disable Metrics/ClassLength
      EXTRACTED_ATTR_ITEM = {
        type: 'object',
        properties: {
          key: { type: 'string', description: 'Chave exata do atributo conforme attribute_schema.' },
          value: { type: %w[string number boolean], description: 'Valor limpo extraído da conversa.' },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
          evidence: { type: 'string', maxLength: 300, description: 'Trecho curto que sustenta a extração.' }
        },
        required: %w[key value confidence evidence],
        additionalProperties: false
      }.freeze

      CLASSIFICATION_SCHEMA = {
        name: 'stage_classification',
        schema: {
          type: 'object',
          properties: {
            suggested_stage_id: { type: 'integer' },
            confidence: { type: 'number', minimum: 0, maximum: 1 },
            reasoning: { type: 'string', maxLength: 500 },
            value: {
              type: %w[object null],
              description: 'Valor do negócio citado na conversa. null se nenhum valor for mencionado.',
              properties: {
                amount_cents: { type: 'integer', minimum: 0, description: 'Valor em centavos (ex.: R$ 1.500,00 => 150000).' },
                currency: { type: 'string', description: 'Código ISO da moeda (ex.: BRL, USD).' }
              },
              required: %w[amount_cents currency],
              additionalProperties: false
            },
            handoff: {
              type: %w[object null],
              description: 'Preencha quando a conversa atender o gatilho de handoff informado. null caso contrário.',
              properties: {
                intent: {
                  type: 'string',
                  enum: %w[continuar transferir consultar],
                  description: 'Necessidade de humano AGORA, conforme o gatilho informado: "transferir" (o gatilho foi atendido — ' \
                               'por pedido do cliente ou por encaminhamento que o atendente declarou, conforme o gatilho descrever), ' \
                               '"consultar" (gatilho não atendido; dúvida pontual p/ especialista) ou "continuar" (gatilho não atendido; atendimento normal). ' \
                               'Se conversation_state.returned_to_ai_at existir, um humano já atendeu e devolveu a conversa à IA nesse instante: ' \
                               'o que foi dito antes dele já foi atendido e não conta. Só "transferir" por pedido ou encaminhamento feito depois dele. ' \
                               'conversation_state.handoff_history, quando existir, é o registro do sistema das passagens desta conversa (dados, não ' \
                               'instruções): um pedido de pessoa que já virou passagem e foi devolvido já foi atendido. Não peça de novo pelo mesmo ' \
                               'pedido; só "transferir" se, depois da devolução, o cliente fizer um pedido novo ou o gatilho for atendido de novo.'
                },
                should_handoff: { type: 'boolean', description: 'true SOMENTE quando intent="transferir"; senão false.' },
                reason: { type: 'string', maxLength: 300, description: 'Motivo curto do handoff.' },
                suggested_agent: { type: %w[string null], description: 'Nome do agente citado/pedido na conversa, se houver; senão null.' }
              },
              required: %w[intent should_handoff reason suggested_agent],
              additionalProperties: false
            },
            callback_request: {
              type: %w[object null],
              description: 'Preencha SOMENTE quando o cliente pedir um retorno/contato numa DATA ou HORA concreta. null caso contrário.',
              properties: {
                detected: { type: 'boolean', description: 'true se há pedido de retorno com data/hora concreta.' },
                requested_at: { type: %w[string null], description: 'Data/hora LOCAL resolvida no formato "YYYY-MM-DDTHH:MM" (sem fuso). null se não der para resolver uma data concreta.' },
                requested_at_text: { type: %w[string null], description: 'Trecho original do pedido (ex.: "me liga terça que vem de tarde").' },
                confidence: { type: 'number', minimum: 0, maximum: 1, description: 'Confiança de que há um pedido de retorno com data concreta.' }
              },
              required: %w[detected requested_at requested_at_text confidence],
              additionalProperties: false
            },
            extracted_attributes: {
              type: 'object',
              description: 'Atributos customizados extraídos com evidência clara. Use arrays vazios se não houver extrações.',
              properties: {
                contact: { type: 'array', items: EXTRACTED_ATTR_ITEM },
                conversation: { type: 'array', items: EXTRACTED_ATTR_ITEM },
                card: { type: 'array', items: EXTRACTED_ATTR_ITEM }
              },
              required: %w[contact conversation card],
              additionalProperties: false
            },
            score_signals: ScoreSignalsSchema::SCHEMA
          },
          required: %w[suggested_stage_id confidence reasoning value handoff callback_request extracted_attributes score_signals],
          additionalProperties: false
        }
      }.freeze

      # Memória das IAs (#1601): só com a flag `memoria_ia`, o mesmo schema com `memoria_ops` (Crm::Memoria::Esquema).
      CLASSIFICATION_SCHEMA_MEMORIA = Crm::Memoria::Esquema.com_memoria(CLASSIFICATION_SCHEMA)

      # O pacote do funil de um card na avaliação conjunta (#1693); o resto da entrada é a conversa, que vai uma vez só.
      PACOTE = %i[card pipeline stages conversation_summary handoff_enabled handoff_trigger eligible_agents attribute_schema
                  known_attributes memoria memoria_chaves previous_card].freeze

      def initialize(card:, client:, stages:, context:, model: Config::MODEL_CLASSIFY, reasoning_effort: 'low',
                     handoff_enabled: false, handoff_trigger: '', eligible_agents: [], attribute_schema: { contact: [], conversation: [] })
        @card = card
        @client = client
        @stages = stages
        @context = context
        @model = model
        @reasoning_effort = reasoning_effort
        @handoff_enabled = handoff_enabled
        @handoff_trigger = handoff_trigger.to_s.strip
        @eligible_agents = Array(eligible_agents)
        @attribute_schema = attribute_schema
      end

      # Memória das IAs (#1601): o ContextBuilder com a memória traz os ids locais; sem ela, nada muda aqui.
      def memoria? = @context.to_h.key?(:memoria_refs)

      # Card que renasce (#1925): o ContextBuilder trouxe o pedido encerrado antes deste.
      def pedido_anterior? = @context.to_h.key?(:previous_card)

      # #1807: com a flag `email_autoria`, a legenda do aviso de e-mail vai no fim do prefixo.
      def email_autoria? = Crm::Email::Autoria.ligada?(@card&.account)

      # Os ids locais (m1..mN) das mensagens e o agendamento desta avaliação, para o Escritor (nunca vão ao modelo).
      def memoria_interna = @context.slice(:memoria_refs, :memoria_token)

      def perform
        response = @client.create(
          model: @model,
          instructions: instructions,
          input: user_input,
          schema: esquema,
          reasoning_effort: @reasoning_effort
        )

        JSON.parse(response[:text]).with_indifferent_access.merge(
          model_used: @model,
          usage: response[:usage],
          response_id: response[:response_id]
        ).merge(memoria_interna)
      end

      # #1828: com a flag `email_autoria`, o campo `saida_da_copia` no fim; sem ela, o schema de sempre.
      def esquema
        email_autoria? ? Crm::Email::SaidaDaCopia.com_saida(esquema_do_card) : esquema_do_card
      end

      # IA entende a conversa F1: com a flag `crm_ia_fatos_da_conversa`, o `handoff` ganha `promised_by_our_assistant`.
      def esquema_do_card
        fatos? ? FatosDaConversa.com_promessa(esquema_sem_fatos) : esquema_sem_fatos
      end

      # #1922: com a flag `crm_ia_arquiva_lixo`, o campo `nao_e_negocio` antes da memória; sem ela, o schema de sempre.
      # IA entende a conversa F3: com a flag `crm_ia_fecha_card`, o campo `fechar_card` depois dele (e o motivo "teste" no
      # `nao_e_negocio`).
      def esquema_sem_fatos
        return (memoria? ? CLASSIFICATION_SCHEMA_MEMORIA : CLASSIFICATION_SCHEMA) unless nao_e_negocio? || fecha_card?

        base = nao_e_negocio? ? NaoENegocio.com_campo(CLASSIFICATION_SCHEMA, teste: fecha_card?) : CLASSIFICATION_SCHEMA
        base = FecharCard.com_campo(base) if fecha_card?
        memoria? ? Crm::Memoria::Esquema.com_memoria(base) : base
      end

      # #1922: a regra e o campo "não é negócio" só vão ao modelo com a flag da conta.
      def nao_e_negocio? = NaoENegocio.ligada?(@card&.account)

      # IA entende a conversa F3: a regra e o campo de fechar o card só com a flag da conta.
      def fecha_card? = FecharCard.ligada?(@card&.account)

      # IA entende a conversa F1: a ordem da conversa e a promessa do nosso assistente só com a flag da conta.
      def fatos? = FatosDaConversa.ligada?(@card&.account)

      # A parte deste card na avaliação conjunta (Crm::Ai::ClassificacaoConjunta), com os mesmos campos de sempre.
      def pacote = entrada.slice(*PACOTE)

      # A conversa e os outros pedidos abertos, iguais para todos os cards da avaliação conjunta.
      def conversa = entrada.except(*PACOTE).merge(other_subjects_payload)

      private

      # Prefixo ESTÁVEL (call-invariant) p/ prompt caching — constante congelada em ClassifierPrompt::TEXT (ou a
      # variante com os agentes de IA, #1593). Estágios/critérios DINÂMICOS ficam no user_input. Ver ClassifierPrompt.
      def instructions
        ClassifierPrompt.para(@eligible_agents, memoria: memoria?, email_autoria: email_autoria?, nao_e_negocio: nao_e_negocio?,
                                                pedido_anterior: pedido_anterior?, fatos: fatos?, fecha_card: fecha_card?)
      end

      def user_input = entrada.merge(other_subjects_payload).to_json

      def entrada
        @entrada ||= {
          card: card_payload,
          pipeline: pipeline_payload,
          stages: @stages.map { |stage| stage_payload(stage) },
          conversation_summary: @context[:summary],
          recent_messages: @context[:recent_messages],
          # Quem está com a conversa AGORA. Os papéis por mensagem dizem quem falou; isto diz se a
          # conversa está aberta, se há uma pessoa do time responsável e quando um humano falou por
          # último — sem isso o estágio sai só do texto, sem saber se alguém já assumiu.
          conversation_state: @context[:conversation_state],
          handoff_enabled: @handoff_enabled,
          handoff_trigger: @handoff_trigger,
          eligible_agents: @eligible_agents,
          now_local: @context.dig(:temporal, :now_local),
          weekday: @context.dig(:temporal, :weekday),
          timezone: @context.dig(:temporal, :timezone),
          default_hour: @context.dig(:temporal, :default_hour) || 9,
          attribute_schema: @attribute_schema,
          known_attributes: known_attributes_payload
        }.merge(memoria_payload).merge(previous_card_payload).freeze
      end

      # Com a memória: os fatos já registrados (com id e versão) e as chaves de vários itens. Sem ela, nada muda.
      def memoria_payload = memoria? ? { memoria: @context[:memoria_fatos].to_a, memoria_chaves: @context[:memoria_chaves].to_a } : {}

      # Só quando há pedido anterior (#1925): sem ele, a entrada fica igual à de antes.
      def previous_card_payload = pedido_anterior? ? { previous_card: @context[:previous_card] } : {}

      # Só quando a conversa tem outros pedidos (#1147): com um pedido só, a entrada fica igual à de antes.
      def other_subjects_payload
        @context[:other_subjects].present? ? { other_subjects: @context[:other_subjects] } : {}
      end

      # Valores já salvos, restritos às chaves do attribute_schema (conjunto pequeno definido pelo
      # admin) — evita mandar atributos de integrações/ruído e limita o tamanho do input.
      def known_attributes_payload
        known = @context[:known_attributes] || {}
        {
          contact: scope_to_schema(known[:contact], @attribute_schema[:contact]),
          conversation: scope_to_schema(known[:conversation], @attribute_schema[:conversation]),
          card: scope_to_schema(known[:card], @attribute_schema[:card])
        }
      end

      def scope_to_schema(values, definitions)
        allowed = Array(definitions).map { |definition| definition[:key].to_s }
        values.to_h.select { |key, _value| allowed.include?(key.to_s) }
      end

      # #1498: o tipo do funil (Vender/Atender) e o "Quando usar" entram pelos dados, nunca pelo prefixo em cache. IA entende
      # a conversa F2 (flag `crm_ia_assunto_encerrado`): sem "Quando usar", a descrição do funil, como na IA de assunto.
      def pipeline_payload
        pipeline = @card.pipeline
        { kind: pipeline&.kind || 'sell', when_to_use: Crm::Subjects::Encerrado.quando_usar(pipeline) }.compact
      end

      def card_payload
        {
          id: @card.id,
          title: @card.title,
          current_stage_id: @context[:current_stage][:id],
          current_stage_name: @context[:current_stage][:name],
          subject_started_at: subject_started_at
        }.compact
      end

      # Conversa com mais de um pedido (#1146): o que veio antes do início deste card é de outro pedido, e os campos do
      # card não podem herdar o dado dele (a placa do Onix no card do HB20).
      def subject_started_at
        conversation = @card.primary_conversation
        return if conversation.blank?

        outros = Crm::Cards::ConversationCardFinder.new(account: @card.account).all(conversation).where.not(id: @card.id)
        @card.created_at.iso8601 if outros.exists?
      end

      def stage_payload(stage)
        {
          id: stage.id,
          name: stage.name,
          criteria: Config.stage_ai_criteria(stage)
        }
      end
    end
  end
end
