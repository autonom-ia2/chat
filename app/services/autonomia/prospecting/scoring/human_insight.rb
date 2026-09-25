# Frase de uma linha que lê a nota (porte de buildHumanInsight do human-insight.ts do Orth, #681): a categoria pelo
# corte do modo e os 3 componentes que mais pesaram (pontos sobre peso). Componente com peso zero, zerado por filtro,
# não entra. Duas trocas em relação ao Orth: "GBP" vira "GMN" e o separador é dois-pontos, não travessão.
module Autonomia::Prospecting::Scoring::HumanInsight
  GBP_CUTS = [[65, 'high'], [40, 'medium']].freeze
  GENERAL_CUTS = [[70, 'high'], [50, 'medium']].freeze
  STRONG_RATIO = 0.5
  MAX_SIGNALS = 3
  KEYS = Autonomia::Prospecting::Scoring::EffectiveWeights::KEYS
  I18N_SCOPE = 'autonomia.prospecting.scoring.human_insight'.freeze

  module_function

  def build(total:, mode:, components:)
    mode = mode == 'general' ? 'general' : 'gbp'
    category = I18n.t("categories.#{mode}.#{category_level(total, mode)}", scope: I18N_SCOPE)
    signals = top_signals(components, mode)
    return category if signals.empty?

    I18n.t('sentence', scope: I18N_SCOPE, category: category, signals: signals.join(', '))
  end

  def category_level(total, mode)
    cuts = mode == 'general' ? GENERAL_CUTS : GBP_CUTS
    cuts.find { |minimum, _level| total >= minimum }&.last || 'low'
  end

  def top_signals(components, mode)
    ranked = components.each_with_index.filter_map do |item, index|
      next unless KEYS.include?(item['key']) && item['weight'].positive?

      [item['key'], item['points'].to_f / item['weight'], index]
    end
    phrases = ranked.sort_by { |_key, ratio, index| [-ratio, index] }.map do |key, ratio, _index|
      I18n.t("signals.#{mode}.#{key}.#{ratio >= STRONG_RATIO ? 'strong' : 'weak'}", scope: I18N_SCOPE)
    end
    phrases.uniq.first(MAX_SIGNALS)
  end
end
