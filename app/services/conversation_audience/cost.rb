# What a search costs on the account's own AI key (#2277), before and while it runs.
#
# The estimate comes from the quality eval on 1,381 real conversations (27/10/2026): the reader's input runs at ~2.85
# characters per token and each batch answers with ~1,500 output tokens (reasoning included), US$ 0.40 for the whole
# account. The ceiling is twice the estimate: the search stops there and asks before spending more.
module ConversationAudience::Cost
  CHARS_PER_TOKEN = 2.85
  OUTPUT_PER_BATCH = 1500
  CEILING_FACTOR = 2
  # Batch calls take ~10–20 s each and run 6 at a time (ConversationAudience::Reader::PARALLEL).
  SECONDS_PER_WAVE = 20

  module_function

  def estimate_usd(chars, batches)
    model = ConversationAudience::Reader::MODEL
    Crm::Ai::Pricing.cost(model: model, input_tokens: (chars / CHARS_PER_TOKEN).ceil,
                          output_tokens: batches * OUTPUT_PER_BATCH).round(4)
  end

  def minutes(batches)
    waves = (batches.to_f / ConversationAudience::Reader::PARALLEL).ceil
    [(waves * SECONDS_PER_WAVE / 60.0).ceil, 1].max
  end

  # The real cost of one call, from the usage the API returned.
  def of(model, usage)
    tokens = Crm::Ai::UsageRecorder.extract_tokens(usage)
    Crm::Ai::Pricing.cost(model: model, input_tokens: tokens[:input], cached_tokens: tokens[:cached],
                          cache_write_tokens: tokens[:cache_write], output_tokens: tokens[:output])
  end

  # USD → BRL with the rate the AI spend page uses; nil when the rate is unavailable (the screen shows dollars).
  def brl(usd, rate)
    return if usd.nil? || rate.nil?

    (BigDecimal(usd.to_s) * BigDecimal(rate.to_s)).round(2).to_f
  end

  def usd_brl_rate
    Crm::Ai::ExchangeRate.current[:rate]
  end
end
