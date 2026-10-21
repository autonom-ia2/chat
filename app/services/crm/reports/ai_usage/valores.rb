# The money side of the AI usage report (#1969): cost in USD/BRL, exchange rate and cache savings. Only who sees the
# account's costs (administrator or financial_view) gets it; `@com_valores` false turns every value off.
module Crm::Reports::AiUsage::Valores
  private

  # Economia LÍQUIDA do cache: desconto das LEITURAS menos a sobretaxa das ESCRITAS. Contar só a
  # leitura inflava o número na família 5.6, que cobra 1,25x o input para gravar no cache — parte do
  # que se economiza relendo já foi paga na gravação. Modelo sem `cache_write` na tabela cai no
  # próprio input (sobretaxa zero), preservando o histórico 5.4. Pode ficar NEGATIVO (muita escrita,
  # pouca releitura): é informação real, não erro, e sinaliza cache mal aproveitado.
  def cache_savings_usd
    cache_delta_usd(:cached_tokens) { |r| r[:input].to_d - r[:cached].to_d } -
      cache_delta_usd(:cache_write_tokens) { |r| (r[:cache_write] || r[:input]).to_d - r[:input].to_d }
  end

  # Soma tokens de +column+ por modelo e aplica o delta de tarifa que o bloco calcula (nunca negativo).
  def cache_delta_usd(column)
    usage_scope.group(:model).sum(column).sum do |model, tokens|
      delta = [yield(Crm::Ai::Pricing.rate(model)), 0.to_d].max
      (tokens.to_i * delta) / 1_000_000.to_d
    end
  end

  def exchange_rate
    @exchange_rate ||= Crm::Ai::ExchangeRate.current
  end

  def exchange_rate_payload
    {
      pair: 'USD-BRL',
      rate: exchange_rate[:rate]&.to_d&.round(6)&.to_f,
      fetched_at: exchange_rate[:fetched_at],
      rate_unavailable: exchange_rate[:rate_unavailable] == true
    }
  end

  def money_payload(cost_usd)
    return {} unless @com_valores

    usd = cost_usd.to_d
    payload = { cost_usd: decimal(usd) }
    payload[:cost_brl] = exchange_rate[:rate].present? ? decimal(usd * exchange_rate[:rate].to_d) : nil
    payload[:rate_unavailable] = true if exchange_rate[:rate_unavailable] == true
    payload
  end

  def decimal(value)
    value.to_d.round(6).to_f
  end

  def percentage(value)
    (value.to_d * 100).round(2).to_f
  end
end
