module Crm
  module Ai
    # Generates a short conversation summary for the card drawer (Conversas tab).
    # Reuses ContextBuilder for the recent-message window, skips MediaEnricher
    # (no transcription/vision round-trips) and caches the result on
    # card.metadata['ai']['summary'] + ['summary_generated_at'] + a source guard
    # so it short-circuits on cache + freshness + unchanged last message.
    class ConversationSummarizer
      Result = Struct.new(:status, :text, :generated_at, :error, keyword_init: true)

      FRESHNESS_TTL_SECONDS = 30.minutes.to_i

      SUMMARY_SCHEMA = {
        name: 'conversation_summary',
        schema: {
          type: 'object',
          properties: {
            summary: { type: 'string', maxLength: 1200 }
          },
          required: %w[summary],
          additionalProperties: false
        }
      }.freeze

      def initialize(card:, force: false)
        @card = card
        @account = card.account
        @force = force
      end

      def perform
        return Result.new(status: :skipped, error: 'ai_disabled') unless Config.enabled?
        return Result.new(status: :skipped, error: 'credentials_missing') unless credential_resolver.configured?
        return Result.new(status: :skipped, error: 'no_conversation') if conversation.blank?

        return cached_result if cache_fresh?

        summary = generate_summary
        return Result.new(status: :failed, error: 'empty_summary') if summary.blank?

        store_summary!(summary)
        Result.new(status: :generated, text: summary, generated_at: generated_at)
      rescue ResponsesClient::Error => e
        Result.new(status: :failed, error: e.message)
      rescue JSON::ParserError
        Result.new(status: :failed, error: 'invalid_llm_json')
      end

      private

      def credential_resolver
        @credential_resolver ||= CredentialResolver.new(account: @account)
      end

      def conversation
        @card.primary_conversation
      end

      # Most recent non-activity message id; used to invalidate the cache when a
      # new message arrives even if the summary is still within the TTL.
      def source_message_id
        @source_message_id ||= conversation.messages
                                           .where(private: false)
                                           .where.not(message_type: :activity)
                                           .maximum(:id)
      end

      def cache_fresh?
        return false if @force

        generated_at_string = ai_metadata['summary_generated_at']
        return false if ai_metadata['summary'].to_s.blank? || generated_at_string.blank?
        return false unless ai_metadata['summary_source_message_id'] == source_message_id

        Time.zone.parse(generated_at_string.to_s) > FRESHNESS_TTL_SECONDS.seconds.ago
      rescue ArgumentError, TypeError
        false
      end

      def cached_result
        Result.new(status: :cached, text: ai_metadata['summary'].to_s, generated_at: ai_metadata['summary_generated_at'])
      end

      def generate_summary
        client = ResponsesClient.new(
          credential: credential_resolver.resolve,
          feature: 'resumo', account: @account, pipeline: @card.pipeline
        )
        context = ContextBuilder.new(card: @card).perform
        response = client.create(
          model: Config::MODEL_SUMMARY,
          instructions: instructions,
          input: user_input(context),
          schema: SUMMARY_SCHEMA,
          reasoning_effort: Config::SUMMARY_REASONING_EFFORT
        )
        JSON.parse(response[:text])['summary'].to_s.strip
      end

      def instructions
        <<~PROMPT.strip
          Você resume conversas de atendimento/vendas em português do Brasil para um card de CRM.
          Produza um resumo objetivo (3 a 5 frases) com o contexto, o que o cliente quer, decisões e próximos passos.
          #{ContextBuilder::ROLES_LEGEND}
          "temporal.now_local" é a data e a hora de agora no fuso do contato, e cada mensagem traz "created_at".
          "conversation_state" diz o status da conversa, se há uma pessoa do time responsável e quando um humano
          falou por último. Situe as pendências no tempo: "aguarda orçamento desde ontem" e "aguarda orçamento há
          três semanas" são situações diferentes, e este resumo é lido depois por outras IAs que decidem quando
          falar com o cliente.
          Não invente informações. Responda apenas com JSON válido no schema solicitado.
        PROMPT
      end

      def user_input(context)
        {
          card: { id: @card.id, title: @card.title },
          current_stage: context[:current_stage],
          temporal: context[:temporal],
          conversation_state: context[:conversation_state],
          recent_messages: context[:recent_messages]
        }.to_json
      end

      def store_summary!(summary)
        @generated_at = Time.current.iso8601
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] = (metadata['ai'] || {}).merge(
          'summary' => summary,
          'summary_generated_at' => @generated_at,
          'summary_source_message_id' => source_message_id,
          'summary_model_used' => Config::MODEL_SUMMARY
        )
        @card.update!(metadata: metadata)
      end

      def generated_at
        @generated_at || ai_metadata['summary_generated_at']
      end

      def ai_metadata
        (@card.metadata || {}).fetch('ai', {}).to_h
      end
    end
  end
end
