# Os números do consultor, formatados pelo servidor (#1110, F5, D5.1). O LLM escreve com marcadores `{{chave}}` e
# nunca com o número: `render` troca cada marcador pelo valor **atual** do fato, no idioma e na moeda da conta. O
# texto guardado no run continua com marcadores, então o gasto, que muda a cada 30 min, não pede nova chamada à IA.
#
# - Cada chave tem um tipo fixo (TYPES, a tabela §2 do desenho); o mesmo tipo vale para a tela e para o WhatsApp.
# - Marcador sem valor (nil, vazio ou chave sem tipo) ou malformado → `render` devolve nil, e quem chama volta ao
#   texto da regra. Nunca sai texto com buraco nem com chave à mostra.
# - A leitura do marcador é por posição de caractere (`String#index`), sem regex: o texto é saída de máquina num
#   formato que nós definimos, não texto de pessoa sendo interpretado.
# - Dinheiro com centavos só quando existem ("R$ 842", "R$ 163,51"), como `metaAdsHelpers.amount` no painel.
module Crm::MetaAds::Advisor::Format
  SCOPE = 'meta_ads_advisor'.freeze
  DEFAULT_LOCALE = :en
  OPEN = '{{'.freeze
  CLOSE = '}}'.freeze
  MONEY_FORMAT = '%u %n'.freeze
  MINUTE = 60
  HOUR = 60 * MINUTE
  DAY = 24 * HOUR
  # A partir de 48 h a duração vira dias; abaixo, horas e minutos.
  DAYS_FROM = 48 * HOUR

  TYPES = {
    'count' => :count, 'value' => :money, 'days' => :days, 'ad_name' => :text,
    'median_seconds' => :duration, 'answered' => :count, 'unanswered' => :count, 'target_seconds' => :duration,
    'window_days' => :days,
    'conversations' => :count, 'unknown' => :count, 'identified_pct' => :percent,
    'sales' => :count, 'spend' => :money, 'cost_per_sale' => :money, 'target_cost_per_sale' => :money,
    'ctr_drop_pct' => :percent, 'frequency_7d' => :decimal1,
    'max_increase_pct' => :percent, 'weeks' => :count, 'cooldown_days' => :days,
    'cpm_change_pct' => :percent, 'cpm_recent' => :money, 'cpm_baseline' => :money,
    'missing_conversations' => :count
  }.freeze

  module_function

  # facts: { chave => valor cru } (chave string ou símbolo). nil quando algum marcador não tem valor ou está malformado.
  def render(template, facts, locale:, currency:)
    parts = split_markers(template)
    return if parts.nil?

    values = facts.to_h.stringify_keys
    locale = supported(locale)
    formatted = parts.filter_map(&:last).index_with { |key| fact(key, values[key], locale: locale, currency: currency) }
    return if formatted.value?(nil)

    parts.map { |text, key| key ? text + formatted[key] : text }.join
  end

  # [[texto antes, chave do marcador ou nil no fim], ...]. nil sem texto, com `{{` sem `}}` ou com `}}` solto.
  def split_markers(template)
    return if template.nil?

    parts = []
    position = 0
    while (opening = template.index(OPEN, position))
      before = template[position...opening]
      closing = template.index(CLOSE, opening + OPEN.size)
      return if before.include?(CLOSE) || closing.nil?

      parts << [before, template[(opening + OPEN.size)...closing].strip]
      position = closing + CLOSE.size
    end
    rest = template[position..]
    rest.include?(CLOSE) ? nil : parts << [rest, nil]
  end

  # O valor de uma chave já formatado; nil sem tipo ou sem valor.
  def fact(key, raw, locale:, currency:)
    type = TYPES[key.to_s]
    return if type.nil? || raw.blank?

    value(type, raw, locale: locale, currency: currency)
  end

  def value(type, raw, locale:, currency: nil)
    locale = supported(locale)
    case type
    when :money then money(raw, currency, locale)
    when :count, :days then integer(raw, locale)
    when :percent then "#{integer(raw.to_f * 100, locale)}%"
    when :decimal1 then decimal1(raw, locale)
    when :duration then duration(raw, locale)
    when :text then raw.to_s
    end
  end

  def money(raw, currency, locale)
    amount = raw.to_f.round(2)
    ActiveSupport::NumberHelper.number_to_currency(
      amount, unit: t('currency_units', locale).fetch(currency.to_s.to_sym, currency.to_s), format: MONEY_FORMAT,
              precision: (amount % 1).zero? ? 0 : 2, separator: t('number.separator', locale), delimiter: t('number.delimiter', locale)
    )
  end

  def integer(raw, locale)
    ActiveSupport::NumberHelper.number_to_delimited(raw.to_f.round, delimiter: t('number.delimiter', locale))
  end

  def decimal1(raw, locale)
    ActiveSupport::NumberHelper.number_to_rounded(raw.to_f, precision: 1, separator: t('number.separator', locale),
                                                            delimiter: t('number.delimiter', locale))
  end

  # Sempre para baixo, como o `duration` da tela (§5.3): "menos de 1 min", "6 min", "1 h 20 min", "2 dias".
  def duration(raw, locale)
    seconds = raw.to_f.floor
    return t('duration.less_than_minute', locale) if seconds < MINUTE
    return t('duration.minutes', locale, count: seconds / MINUTE) if seconds < HOUR
    return t('duration.days', locale, count: seconds / DAY) if seconds >= DAYS_FROM

    hours, rest = seconds.divmod(HOUR)
    minutes = rest / MINUTE
    minutes.zero? ? t('duration.hours', locale, count: hours) : t('duration.hours_minutes', locale, hours: hours, minutes: minutes)
  end

  # Idioma sem texto do consultor (o catálogo é en + pt_BR) cai no inglês.
  def supported(locale)
    locale = locale.to_s
    known = I18n.available_locales.map(&:to_s).include?(locale) && I18n.exists?("#{SCOPE}.duration.minutes", locale)
    known ? locale : DEFAULT_LOCALE.to_s
  end

  def t(key, locale, **)
    I18n.t("#{SCOPE}.#{key}", locale: locale, **)
  end
end
