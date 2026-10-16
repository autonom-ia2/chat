module Crm
  module Ai
    class Evaluator
      Result = Struct.new(:status, :suggestion, :error, keyword_init: true)

      def initialize(card:, trigger: 'message')
        @card = card
        @account = card.account
        @trigger = trigger
      end

      def perform
        return Result.new(status: :skipped, error: 'ai_disabled') unless Config.enabled?
        return Result.new(status: :skipped, error: 'credentials_missing') unless credential_resolver.configured?
        return Result.new(status: :skipped, error: 'pipeline_ai_disabled') unless pipeline_ai_enabled?
        return Result.new(status: :skipped, error: 'debounced') if debounced? && @trigger != 'manual'
        return Result.new(status: :skipped, error: 'card_not_open') unless @card.open?
        # Multifunil (#1147): só o assunto atual da conversa é avaliado; "Avaliar agora" é escolha da pessoa.
        return Result.new(status: :skipped, error: 'not_current_subject') unless @trigger == 'manual' || ::Crm::Cards::CurrentSubject.card?(@card)

        # O funil do card no começo: a resposta do modelo é sobre as etapas DELE (#1711).
        @pipeline_inicial = @card.pipeline_id
        classification = classify_stage
        result = apply_classification(classification)
        return result if @pipeline_mudou

        refresh_post_classification_context!
        classification = refresh_handoff_classification_if_needed(classification, result)
        run_handoff(classification)
        run_callback(classification)
        attribute_extraction.apply(classification[:extracted_attributes])
        ScoreApplier.new(card: @card, signals: classification[:score_signals]).perform
        result
      rescue ResponsesClient::Error => e
        Result.new(status: :failed, error: e.message)
      rescue JSON::ParserError
        Result.new(status: :failed, error: 'invalid_llm_json')
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
        # O card mudou de funil depois da última avaliação (a IA de assunto o levou, #1711): ela era sobre outras etapas.
        return false if ai_metadata['last_evaluated_pipeline_id'].present? && ai_metadata['last_evaluated_pipeline_id'].to_i != @card.pipeline_id

        Time.parse(last_evaluated_at) > Config::DEBOUNCE_SECONDS.seconds.ago
      rescue ArgumentError
        false
      end

      def classify_stage(enrich_media: true)
        MediaEnricher.new(card: @card).perform if enrich_media && Config.media_enabled?
        # cache_key_scope: :feature — o prefixo do classify é conta-agnóstico (StageClassifier#instructions),
        # então roteamos por feature só (sem account) p/ consolidar o hit-rate de cache entre contas.
        client = ResponsesClient.new(
          credential: credential_resolver.resolve,
          feature: 'avaliacao_card', account: @account, pipeline: @card.pipeline,
          cache_key_scope: :feature
        )
        context = ContextBuilder.new(card: @card).perform
        model = auto_move_allowed? ? Config::MODEL_AUTO_MOVE : Config::MODEL_CLASSIFY
        effort = Config::CLASSIFY_REASONING_EFFORT

        StageClassifier.new(
          card: @card, client: client, stages: stages, context: context, model: model, reasoning_effort: effort,
          handoff_enabled: handoff_config[:enabled], handoff_trigger: handoff_config[:trigger],
          eligible_agents: eligible_agent_names, attribute_schema: attribute_extraction.schema
        ).perform
      end

      def handoff_config
        @handoff_config ||= Config.handoff_settings(@card.stage, @card.pipeline)
      end

      def refresh_post_classification_context!
        @card.reload
        @handoff_config = nil
      end

      def refresh_handoff_classification_if_needed(classification, result)
        return classification unless result.status == :auto_moved
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
        return unless handoff_config[:enabled]

        HandoffExecutor.new(card: @card, handoff: classification[:handoff], trigger: @trigger).perform
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
        return Result.new(status: :skipped, error: 'pipeline_changed') if @pipeline_mudou

        target_stage = stages.find { |stage| stage.id == classification[:suggested_stage_id].to_i }
        return Result.new(status: :skipped, error: 'unknown_stage') if target_stage.blank?
        return Result.new(status: :skipped, error: 'same_stage') if target_stage.id == @card.stage_id

        confidence = classification[:confidence].to_f
        if auto_move_allowed? && confidence >= Config::AUTO_MOVE_THRESHOLD && stage_criteria_present?(target_stage)
          suggestion = SuggestionRecorder.new(
            card: @card,
            from_stage: @card.stage,
            to_stage: target_stage,
            confidence: confidence,
            reasoning: classification[:reasoning],
            model_used: classification[:model_used],
            status: :auto_applied,
            metadata: { trigger: @trigger }
          ).perform

          SuggestionApplier.new(card: @card, suggestion: suggestion, actor: nil, auto: true).perform
          Result.new(status: :auto_moved, suggestion: suggestion)
        elsif confidence >= Config::SUGGESTION_THRESHOLD
          suggestion = SuggestionRecorder.new(
            card: @card,
            from_stage: @card.stage,
            to_stage: target_stage,
            confidence: confidence,
            reasoning: classification[:reasoning],
            model_used: classification[:model_used],
            status: :pending,
            metadata: { trigger: @trigger }
          ).perform
          Result.new(status: :suggested, suggestion: suggestion)
        else
          Result.new(status: :below_threshold)
        end
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
          # #1711: o card mudou de funil enquanto o modelo pensava (a IA de assunto o levou para o funil do pedido). A
          # resposta é sobre as etapas do funil antigo: descartada, sem carimbo, para a avaliação nova não ser pulada.
          @pipeline_mudou = @pipeline_inicial.present? && @card.pipeline_id != @pipeline_inicial
          next if @pipeline_mudou

          metadata = (@card.metadata || {}).deep_dup
          metadata['ai'] = (metadata['ai'] || {}).merge(
            'last_evaluated_at' => Time.current.iso8601,
            'last_evaluated_pipeline_id' => @card.pipeline_id,
            'last_model_used' => classification[:model_used],
            'last_trigger' => @trigger
          )
          attributes = { metadata: metadata }
          apply_ai_value!(metadata['ai'], classification[:value], attributes)
          @card.update!(attributes)
        end
      end

      # O valor achado na conversa (Crm::Ai::ValorAchado).
      def apply_ai_value!(ai_metadata, value, attributes)
        ValorAchado.aplicar!(@card, ai_metadata, value, attributes)
      end
    end
  end
end
