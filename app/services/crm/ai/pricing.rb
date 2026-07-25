module Crm
  module Ai
    # Tabela de preço por modelo p/ ESTIMAR custo (USD por 1M tokens).
    #
    # Valores DEFAULT = preço de tabela "Standard" da OpenAI (developers.openai.com/api/docs/pricing,
    # família 5.6 consultada 2026-07-25). Modelos novos/preços alterados: ajustar aqui OU sem deploy
    # via ENV (1M tokens, "input,cached,output" com 4o campo OPCIONAL "cache_write"):
    #   CRM_AI_PRICE_GPT_5_4="2.5,0.25,15"
    #   CRM_AI_PRICE_GPT_5_6_LUNA="1,0.1,6,1.25"
    # A chave da ENV é o modelo em UPPER, com tudo que não for [A-Z0-9] virando "_".
    # Não cobre Batch (-50%), Flex/Priority, nem áudio/TTS — só os modelos de texto em uso no CRM.
    module Pricing
      ZERO_RATE = { input: 0.0, cached: 0.0, output: 0.0 }.freeze

      # USD / 1M tokens. TRÊS tarifas de INPUT:
      #   input       = token novo, não cacheado
      #   cached      = LEITURA de cache (90% de desconto)
      #   cache_write = ESCRITA no cache. A família 5.6 cobra 1,25x o input; os modelos 5.4 não têm
      #                 tarifa própria e caem no `input` (preserva o comportamento histórico).
      # Família 5.6 (Sol/Terra/Luna) incluída para a página de gestão de IA precificar qualquer
      # modelo em uso: modelo AUSENTE daqui cai em ZERO_RATE e o custo é gravado como 0 SEM erro
      # (falha silenciosa). Terra tem a MESMA tarifa do gpt-5.4 — troca de geração sem custo extra.
      DEFAULT_RATES = {
        'gpt-5.6-sol' => { input: 5.0, cached: 0.5, cache_write: 6.25, output: 30.0 },
        'gpt-5.6-terra' => { input: 2.5, cached: 0.25, cache_write: 3.125, output: 15.0 },
        'gpt-5.6-luna' => { input: 1.0, cached: 0.1, cache_write: 1.25, output: 6.0 },
        'gpt-5.4' => { input: 2.5, cached: 0.25, output: 15.0 },
        'gpt-5.4-mini' => { input: 0.75, cached: 0.075, output: 4.5 },
        'gpt-5.4-nano' => { input: 0.2, cached: 0.02, output: 1.25 }
      }.freeze

      def self.rate(model)
        env = ENV.fetch("CRM_AI_PRICE_#{model.to_s.upcase.gsub(/[^A-Z0-9]/, '_')}", nil)
        if env.present?
          input, cached, output, cache_write = env.split(',').map { |v| v.to_s.strip.to_f }
          parsed = { input: input.to_f, cached: cached.to_f, output: output.to_f }
          # 4o campo OPCIONAL: sem ele a escrita em cache cai no `input` (formato antigo segue valendo).
          parsed[:cache_write] = cache_write if cache_write
          return parsed
        end
        DEFAULT_RATES[model.to_s] || ZERO_RATE
      end

      # Custo estimado em USD. input_tokens da Responses API JÁ inclui os cacheados E os escritos
      # em cache (confirmado por probe: input=4176 com cache_write=4173 na 1a chamada e
      # cached=4173 na 2a), então o billable a tarifa cheia = input - cached - cache_write.
      # Cada fatia cobra a SUA tarifa; sem `cache_write` na tabela, a escrita cai no `input`.
      def self.cost(model:, input_tokens: 0, cached_tokens: 0, output_tokens: 0, cache_write_tokens: 0)
        r = rate(model)
        cached = cached_tokens.to_i
        written = cache_write_tokens.to_i
        billable_input = [input_tokens.to_i - cached - written, 0].max
        write_rate = r[:cache_write] || r[:input]
        ((billable_input * r[:input]) + (cached * r[:cached]) +
          (written * write_rate) + (output_tokens.to_i * r[:output])) / 1_000_000.0
      end
    end
  end
end
