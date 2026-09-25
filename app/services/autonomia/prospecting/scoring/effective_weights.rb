# Pesos dos 6 componentes do Orth e o ajuste pelos filtros ativos da busca (porte de DEFAULT_WEIGHTS e
# adaptWeightsToContext do score.ts do Orth, #681). O filtro zera ou reduz o peso do sinal que ele já garante e o total
# volta a 100; a sobra do arredondamento vai para o maior peso. Filtros no formato de advanced_filters da busca:
# 'yes'/'no' para presença, números (em texto ou não) para rating_min, rating_max e reviews_min.
module Autonomia::Prospecting::Scoring::EffectiveWeights
  DEFAULT = {
    'website' => 30,
    'phone' => 10,
    'rating' => 20,
    'volume' => 15,
    'activity' => 10,
    'photos' => 15
  }.freeze
  KEYS = DEFAULT.keys.freeze
  PRESENCE_FILTERS = { 'has_website' => 'website', 'has_phone' => 'phone', 'has_photos' => 'photos' }.freeze
  PRESENCE_VALUES = [true, false, 'yes', 'no'].freeze

  module_function

  def for(weights, filters)
    base = DEFAULT.merge(weights.to_h.stringify_keys.slice(*KEYS))
    adapted = adapt(base, filters.to_h.stringify_keys)
    total = adapted.values.sum
    return base if total <= 0
    return adapted if total == 100

    normalize(adapted, total)
  end

  def adapt(base, filters)
    weights = base.dup
    PRESENCE_FILTERS.each { |filter, key| weights[key] = 0 if PRESENCE_VALUES.include?(filters[filter]) }
    rating_factors = [rating_min_factor(number(filters['rating_min'])), rating_max_factor(number(filters['rating_max']))]
    weights['rating'] = scaled(weights['rating'], rating_factors)
    weights['volume'] = scaled(weights['volume'], [volume_factor(number(filters['reviews_min']))])
    weights
  end

  # Nota mínima alta corta o rating; nota máxima baixa corta de novo, sobre o que sobrou (como no Orth).
  def rating_min_factor(rating_min)
    return unless rating_min
    return 0.15 if rating_min >= 4.5

    0.4 if rating_min >= 4.0
  end

  def rating_max_factor(rating_max)
    0.3 if rating_max && rating_max <= 3.0
  end

  def volume_factor(reviews_min)
    return unless reviews_min
    return 0 if reviews_min >= 50

    0.4 if reviews_min >= 20
  end

  def scaled(weight, factors)
    factors.compact.reduce(weight) { |value, factor| (value * factor).round }
  end

  def normalize(weights, total)
    factor = 100.0 / total
    normalized = weights.transform_values { |value| (value * factor).round }
    remainder = 100 - normalized.values.sum
    return normalized if remainder.zero?

    largest = normalized.keys.reduce { |best, key| normalized[best] >= normalized[key] ? best : key }
    normalized.merge(largest => normalized[largest] + remainder)
  end

  def number(value)
    return if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end
end
