# Limite de uso da Insights API da Meta (#1073, CA-2.2).
#
# Toda resposta da Meta diz, nos cabeçalhos, quanto do limite já foi gasto (em %), e quantos minutos faltam
# para liberar quando estourou:
# - x-business-use-case-usage: { "<id>": [{ type, call_count, total_cputime, total_time,
#   estimated_time_to_regain_access }] }, por portfólio e tipo de chamada (ads_insights, ads_management…)
# - x-fb-ads-insights-throttle: { app_id_util_pct, acc_id_util_pct }
# - x-app-usage: { call_count, total_cputime, total_time }
#
# Acima de LIMIT_PCT, ou quando a Meta recusa por limite, a conta de anúncios fica em pausa pelo tempo que
# a Meta indicar (ou DEFAULT_PAUSE): toda leitura de insights dela é pulada até lá. Limite de uso nunca
# marca a conexão como inválida; fica só no log.
class Crm::MetaAds::Insights::Usage
  LIMIT_PCT = 75
  DEFAULT_PAUSE = 15.minutes
  MIN_PAUSE = 5.minutes
  # Códigos de erro de limite de taxa da Graph e da Marketing API (80000–80014: limite por portfólio).
  RATE_LIMIT_CODES = ([4, 17, 32, 613] + (80_000..80_014).to_a).freeze
  KEY_PREFIX = 'crm:meta_ads:insights:pause'.freeze
  PCT_FIELDS = %w[call_count total_cputime total_time app_id_util_pct acc_id_util_pct].freeze
  REGAIN_FIELD = 'estimated_time_to_regain_access'.freeze

  def self.paused?(ad_account_id)
    Redis::Alfred.exists?(key(ad_account_id))
  end

  # Lê o resultado da Graph e pausa a conta de anúncios se o limite pedir. true quando pausou.
  def self.track!(ad_account_id, result)
    usage = new(result.usage_headers)
    limited = RATE_LIMIT_CODES.include?(result.error_code)
    return false unless limited || usage.percent >= LIMIT_PCT

    pause = [usage.regain_time || DEFAULT_PAUSE, MIN_PAUSE].max
    Redis::Alfred.set(key(ad_account_id), 1, ex: pause.to_i)
    Rails.logger.warn("[MetaAdsInsights] pause act_#{ad_account_id} for #{pause.to_i}s " \
                      "usage=#{usage.percent}% code=#{result.error_code.inspect}")
    true
  end

  def self.key(ad_account_id)
    "#{KEY_PREFIX}:#{ad_account_id}"
  end

  def initialize(headers)
    @entries = Array(headers).flat_map { |_name, value| entries(value) }
  end

  # Maior percentual informado em qualquer cabeçalho.
  def percent
    @entries.flat_map { |entry| PCT_FIELDS.map { |field| entry[field].to_f } }.max.to_f
  end

  # Maior tempo para liberar informado (a Meta dá em minutos); nil quando ninguém informou.
  def regain_time
    minutes = @entries.map { |entry| entry[REGAIN_FIELD].to_i }.max.to_i
    minutes.positive? ? minutes.minutes : nil
  end

  private

  # Cada cabeçalho é JSON: um objeto de números, ou um objeto de listas de objetos (o de portfólio).
  def entries(value)
    parsed = JSON.parse(value.to_s)
    return [] unless parsed.is_a?(Hash)
    return [parsed] unless parsed.values.any?(Array)

    parsed.values.flatten.grep(Hash)
  rescue JSON::ParserError
    []
  end
end
