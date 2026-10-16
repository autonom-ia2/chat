module Crm
  module Ai
    class Evaluator
      Result = Struct.new(:status, :suggestion, :error, keyword_init: true)

      # tocado (#1693): a IA de assunto disse que a mensagem é sobre este card; ele é avaliado mesmo fora do foco.
      def initialize(card:, trigger: 'message', tocado: false)
        @card = card
        @account = card.account
        @trigger = trigger
        @tocado = tocado
      end

      def perform
        pular = motivo_para_pular
        return Result.new(status: :skipped, error: pular) if pular

        aplicar(classify_stage)
      rescue ResponsesClient::Error => e
        Result.new(status: :failed, error: e.message)
      rescue JSON::ParserError
        Result.new(status: :failed, error: 'invalid_llm_json')
      end

      # As guardas de sempre, uma por card; nil quando o card pode ser avaliado.
      def motivo_para_pular
        return 'ai_disabled' unless Config.enabled?
        return 'credentials_missing' unless credential_resolver.configured?
        return 'pipeline_ai_disabled' unless pipeline_ai_enabled?
        return 'debounced' if debounced? && @trigger != 'manual'
        return 'card_not_open' unless @card.open?
        # Multifunil (#1147): só o assunto atual da conversa é avaliado; "Avaliar agora" é escolha da pessoa e o card
        # tocado pela mensagem (#1693) é escolha da IA de assunto.
        return 'not_current_subject' unless @trigger == 'manual' || @tocado || ::Crm::Cards::CurrentSubject.card?(@card)

        nil
      end

      # O que vem depois da resposta da IA, igual para a avaliação de um card e para a conjunta (#1693). conjunta: depois
      # de mover, o pedido de atendente só é relido se a etapa nova tem outra regra (a conjunta é uma chamada por
      # mensagem; a de um card segue relendo como sempre). passar: este card pode passar a conversa (na conjunta, só o
      # card em que está o pedido, ou o principal, Crm::Ai::AvaliacaoConjunta). pelo_card: o pedido que o cliente ligou a
      # este card, fora do principal, vai pela regra dele mesmo fora do foco (decisão 1a do Rodrigo, 16/10).
      def aplicar(classification, conjunta: false, passar: true, pelo_card: false)
        @passar = passar
        @pelo_card = pelo_card
        regra = handoff_config.slice(:enabled, :trigger) if conjunta
        result = apply_classification(classification)
        refresh_post_classification_context!
        classification = refresh_handoff_classification_if_needed(classification, result, regra)
        run_handoff(classification)
        run_callback(classification)
        attribute_extraction.apply(classification[:extracted_attributes])
        ScoreApplier.new(card: @card, signals: classification[:score_signals]).perform
        result
      end

      # O classificador deste card, com o pacote do funil dele. A avaliação conjunta (#1693) usa o pacote; `fora` são os
      # outros cards tocados, que saem da lista de outros pedidos.
      def stage_classifier(client:, fora: [])
        StageClassifier.new(
          card: @card, client: client, stages: stages, context: ContextBuilder.new(card: @card, fora: fora).perform,
          model: modelo, reasoning_effort: Config::CLASSIFY_REASONING_EFFORT,
          handoff_enabled: handoff_config[:enabled], handoff_trigger: handoff_config[:trigger],
          eligible_agents: eligible_agent_names, attribute_schema: attribute_extraction.schema
        )
      end

      def modelo = auto_move_allowed? ? Config::MODEL_AUTO_MOVE : Config::MODEL_CLASSIFY

      # cache_key_scope: :feature — o prefixo do classify é conta-agnóstico (StageClassifier#instructions),
      # então roteamos por feature só (sem account) p/ consolidar o hit-rate de cache entre contas.
      def classify_client
        ResponsesClient.new(credential: credential_resolver.resolve, feature: 'avaliacao_card', account: @account,
                            pipeline: @card.pipeline, cache_key_scope: :feature)
      end

      private

      def credential_resolver
        @credential_resolver ||= CredentialResolver.new(account: @account)
      end

      def pipeline_ai_enabled?
        settings = Config.pipeline_ai_settings(@card.pipeline)
        settings[:enabled] != false
      end

      def debounced?
        last_evaluated_at = ai_metadata['last_evaluated_at']
        return false if last_evaluated_at.blank?

        Time.parse(last_evaluated_at) > Config::DEBOUNCE_SECONDS.seconds.ago
      rescue ArgumentError
        false
      end

      def classify_stage(enrich_media: true)
        MediaEnricher.new(card: @card).perform if enrich_media && Config.media_enabled?
        stage_classifier(client: classify_client).perform
      end

      def handoff_config
        @handoff_config ||= Config.handoff_settings(@card.stage, @card.pipeline)
      end

      def refresh_post_classification_context!
        @card.reload
        @handoff_config = nil
      end

      # regra (#1693): a regra de pedido de atendente que a avaliação conjunta já leu; a mesma regra não é relida.
      def refresh_handoff_classification_if_needed(classification, result, regra = nil)
        return classification unless @passar && result.status == :auto_moved
        return classification if regra && handoff_config.slice(:enabled, :trigger) == regra
        return classification if HandoffIntent.requested?(classification[:handoff])
        return classification unless handoff_config[:enabled]

        handoff_classification = classify_stage(enrich_media: false)
        classification.merge(handoff: handoff_classification[:handoff])
      end

      def eligible_agent_names
        return [] unless handoff_config[:enabled]

        # A conversa que o executor vai passar (#553), e não a primária: com o cliente escrevendo por outra caixa, a lista
        # da primária oferecia ao modelo nomes que o seletor depois descarta (#1385).
        conversation = @card.conversa_em_atendimento
        return [] if conversation.blank? || conversation.inbox.blank?

        # Acesso por funil (#1148, parte C): o modelo só conhece quem pode receber a conversa.
        # #1593: com o pedido pelo nome, os agentes de IA que podem receber entram com o rótulo; o modelo decide.
        Crm::Access::Recipients.inbox_members(conversation).pluck(:name) + Crm::AgentesIa.rotulos_pelo_nome(conversation, handoff_config)
      end

      # Independent of the stage move. Guarded inside the executor; never let a
      # handoff failure break the evaluation result.
      def run_handoff(classification)
        return unless @passar && handoff_config[:enabled]

        HandoffExecutor.new(card: @card, handoff: classification[:handoff], trigger: @trigger, pelo_card: @pelo_card).perform
      rescue StandardError => e
        Rails.logger.error("[CRM AI handoff] #{e.class}: #{e.message}")
      end

      # Cria/atualiza um lembrete quando a IA detectou um pedido de retorno com data concreta.
      # Best-effort: o CallbackScheduler já engole erros, mas guardamos aqui também por simetria —
      # nunca deixa a detecção de retorno quebrar a avaliação do card.
      def run_callback(classification)
        return unless Config.callback_detection_enabled?
        return unless Config.pipeline_callback_enabled?(@card.pipeline)

        Crm::FollowUps::CallbackScheduler.new(card: @card, callback: classification[:callback_request]).perform
      rescue StandardError => e
        Rails.logger.error("[CRM AI callback] #{e.class}: #{e.message}")
      end

      def apply_classification(classification)
        touch_evaluation_metadata(classification)
        target_stage = stages.find { |stage| stage.id == classification[:suggested_stage_id].to_i }
        return Result.new(status: :skipped, error: 'unknown_stage') if target_stage.blank?
        return Result.new(status: :skipped, error: 'same_stage') if target_stage.id == @card.stage_id

        confidence = classification[:confidence].to_f
        if auto_move_allowed? && confidence >= Config::AUTO_MOVE_THRESHOLD && stage_criteria_present?(target_stage)
          suggestion = record_suggestion(target_stage, confidence, classification, :auto_applied)
          SuggestionApplier.new(card: @card, suggestion: suggestion, actor: nil, auto: true).perform
          Result.new(status: :auto_moved, suggestion: suggestion)
        elsif confidence >= Config::SUGGESTION_THRESHOLD
          Result.new(status: :suggested, suggestion: record_suggestion(target_stage, confidence, classification, :pending))
        else
          Result.new(status: :below_threshold)
        end
      end

      def record_suggestion(target_stage, confidence, classification, status)
        SuggestionRecorder.new(
          card: @card, from_stage: @card.stage, to_stage: target_stage, confidence: confidence,
          reasoning: classification[:reasoning], model_used: classification[:model_used], status: status,
          metadata: { trigger: @trigger }
        ).perform
      end

      def auto_move_allowed?
        settings = Config.pipeline_ai_settings(@card.pipeline)
        return false unless settings[:auto_move_enabled]

        return true if Config::AUTO_MOVE_COOLDOWN_SECONDS <= 0

        return false if ai_metadata['last_auto_move_at'].present? &&
                        Time.parse(ai_metadata['last_auto_move_at']) > Config::AUTO_MOVE_COOLDOWN_SECONDS.seconds.ago

        true
      rescue ArgumentError
        false
      end

      def stage_criteria_present?(stage)
        Config.stage_ai_criteria(stage).present?
      end

      def stages
        @stages ||= @card.pipeline.stages.order(:position, :id).to_a
      end

      def attribute_extraction
        @attribute_extraction ||= AttributeExtraction.new(card: @card)
      end

      def ai_metadata
        (@card.metadata || {}).fetch('ai', {}).to_h
      end

      # RELÊ O CARD ANTES DE GRAVAR (revisão da chat#633): a avaliação leva de 15 a 25 s esperando o modelo, e gravar o
      # metadata lido no começo apagava o que chegou nesse meio tempo — o carimbo da devolução à IA
      # (`DevolucaoAIa`), e com ele a guarda que impede a passagem de reatribuir a conversa devolvida.
      def touch_evaluation_metadata(classification)
        # `with_lock` relê o card do banco (lock!), com o carimbo que chegou durante a avaliação.
        @card.with_lock do
          metadata = (@card.metadata || {}).deep_dup
          metadata['ai'] = (metadata['ai'] || {}).merge(
            'last_evaluated_at' => Time.current.iso8601,
            'last_model_used' => classification[:model_used],
            'last_trigger' => @trigger
          )
          attributes = { metadata: metadata }
          apply_ai_value!(metadata['ai'], classification[:value], attributes)
          @card.update!(attributes)
        end
      end

      # Auto-fill the deal value detected in the conversation, writing value_cents
      # directly (product decision: "autopreenche sempre"). The ONLY guard is a
      # human takeover: once someone edits the value manually (value_source =
      # 'human'), a later eval must never undo that correction.
      # #1498: funil de Atender não tem valor de venda; a IA não preenche (a Cobrança guarda o valor que a pessoa digita).
      def apply_ai_value!(ai_metadata, value, attributes)
        return unless @card.pipeline&.counts_as_sale?

        value = value.respond_to?(:with_indifferent_access) ? value.with_indifferent_access : value
        return if value.blank? || value[:amount_cents].blank? || value[:currency].blank?
        return if ai_metadata['value_source'] == 'human'

        amount = value[:amount_cents].to_i
        currency = value[:currency].to_s.upcase
        return if amount == @card.value_cents && currency == @card.currency

        attributes[:value_cents] = amount
        attributes[:currency] = currency
        ai_metadata['value_source'] = 'ai'
        ai_metadata['value_filled_at'] = Time.current.iso8601
      end
    end
  end
end
