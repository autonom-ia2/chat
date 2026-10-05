module Crm
  module Ai
    # Grava 1 evento de consumo por chamada de IA, p/ o dashboard Gestão IA (Fase 3.2).
    # BEST-EFFORT: NUNCA levanta — telemetria não pode quebrar o fluxo de IA. Só metadados:
    # NUNCA prompt, instrução nem resposta.
    class UsageRecorder
      def self.record(account:, feature:, model:, usage: {}, reasoning_effort: nil, latency_ms: nil, pipeline: nil)
        return if account.blank? || feature.blank? || model.blank?

        tokens = extract_tokens(usage)
        event = Crm::AiUsageEvent.create!(
          account_id: id_of(account),
          pipeline_id: id_of(pipeline),
          feature: feature.to_s,
          model: model.to_s,
          reasoning_effort: reasoning_effort.presence&.to_s,
          input_tokens: tokens[:input],
          cached_tokens: tokens[:cached],
          cache_write_tokens: tokens[:cache_write],
          output_tokens: tokens[:output],
          cost_estimate: cost_for(model, tokens),
          latency_ms: latency_ms,
          created_at: Time.current
        )
        notify(event, tokens)
        event
      rescue StandardError => e
        Rails.logger.warn("[crm][ai][usage] record failed feature=#{feature} model=#{model}: #{e.class}: #{e.message}")
        nil
      end

      def self.cost_for(model, tokens)
        Pricing.cost(model: model, input_tokens: tokens[:input], cached_tokens: tokens[:cached],
                     cache_write_tokens: tokens[:cache_write], output_tokens: tokens[:output])
      end

      EVENT_NAME = 'crm.ai_usage'.freeze

      # Quem precisa somar o custo de UM trabalho (o registro de um pedido ao Guia, #861) assina este
      # evento enquanto o trabalho roda. A tabela continua sendo a fonte da Gestão IA; isto é só aviso.
      def self.notify(event, tokens)
        ActiveSupport::Notifications.instrument(
          EVENT_NAME,
          event_id: event.id, feature: event.feature, model: event.model, effort: event.reasoning_effort,
          tokens: { in: tokens[:input], cached: tokens[:cached], out: tokens[:output] },
          cost: event.cost_estimate.to_f, latency_ms: event.latency_ms
        )
      end

      def self.id_of(value)
        return nil if value.blank?

        value.respond_to?(:id) ? value.id : value
      end

      # Aceita o usage da Responses API (input_tokens/output_tokens/input_tokens_details.{cached_tokens,
      # cache_write_tokens}) e o shape de chat (prompt_tokens/completion_tokens/prompt_tokens_details).
      # String/symbol keys. `cache_write_tokens` só existe na família 5.6; ausente vira 0.
      def self.extract_tokens(usage)
        u = (usage || {}).to_h.transform_keys(&:to_s)
        details = (u['input_tokens_details'] || u['prompt_tokens_details'] || {}).to_h.transform_keys(&:to_s)
        {
          input: (u['input_tokens'] || u['prompt_tokens']).to_i,
          output: (u['output_tokens'] || u['completion_tokens']).to_i,
          cached: details['cached_tokens'].to_i,
          cache_write: details['cache_write_tokens'].to_i
        }
      end
    end
  end
end
