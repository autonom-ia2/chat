module Crm
  module Ai
    # Tabela de preço por modelo p/ ESTIMAR custo (USD por 1M tokens).
    #
    # Valores DEFAULT = preço de tabela "Standard" da OpenAI (developers.openai.com/api/docs/pricing,
    # consultado 2026-06-28). Modelos novos/preços alterados: ajustar aqui OU sem deploy via ENV
    # (1M tokens, "input,cached,output"):
    #   CRM_AI_PRICE_GPT_5_4="2.5,0.25,15"
    #   CRM_AI_PRICE_GPT_5_4_MINI="0.75,0.075,4.5"
    # A chave da ENV é o modelo em UPPER, com tudo que não for [A-Z0-9] virando "_".
    # Não cobre Batch (-50%), Flex/Priority, nem áudio/TTS — só os modelos de texto em uso no CRM.
    module Pricing
      ZERO_RATE = { input: 0.0, cached: 0.0, output: 0.0 }.freeze

      # USD / 1M tokens (cached = input cacheado, tarifa com desconto OpenAI).
      # Família 5.6 (Sol/Terra/Luna) incluída para a página de gestão de IA precificar qualquer
      # modelo em uso: modelo AUSENTE daqui cai em ZERO_RATE e o custo é gravado como 0 SEM erro
      # (falha silenciosa). Terra tem a MESMA tarifa do gpt-5.4 — troca de geração sem custo extra.
      DEFAULT_RATES = {
        'gpt-5.6-sol' => { input: 5.0, cached: 0.5, output: 30.0 },
        'gpt-5.6-terra' => { input: 2.5, cached: 0.25, output: 15.0 },
        'gpt-5.6-luna' => { input: 1.0, cached: 0.1, output: 6.0 },
        'gpt-5.4' => { input: 2.5, cached: 0.25, output: 15.0 },
        'gpt-5.4-mini' => { input: 0.75, cached: 0.075, output: 4.5 },
        'gpt-5.4-nano' => { input: 0.2, cached: 0.02, output: 1.25 }
      }.freeze

      def self.rate(model)
        env = ENV.fetch("CRM_AI_PRICE_#{model.to_s.upcase.gsub(/[^A-Z0-9]/, '_')}", nil)
        if env.present?
          input, cached, output = env.split(',').map { |v| v.to_s.strip.to_f }
          return { input: input.to_f, cached: cached.to_f, output: output.to_f }
        end
        DEFAULT_RATES[model.to_s] || ZERO_RATE
      end

      # Custo estimado em USD. input_tokens da Responses API JÁ inclui os cacheados, então o
      # billable não-cacheado = input - cached (cached cobra a tarifa com desconto).
      def self.cost(model:, input_tokens: 0, cached_tokens: 0, output_tokens: 0)
        r = rate(model)
        billable_input = [input_tokens.to_i - cached_tokens.to_i, 0].max
        ((billable_input * r[:input]) + (cached_tokens.to_i * r[:cached]) + (output_tokens.to_i * r[:output])) / 1_000_000.0
      end
    end
  end
end
