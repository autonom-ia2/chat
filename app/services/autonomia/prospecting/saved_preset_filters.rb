# Filtros de uma jogada salva (#732): as chaves da gaveta de filtros (advancedLeadFilters.js no front, advanced_filters
# do SearchRunner no motor), com os valores que a gaveta produz. Vazio sai; número em texto vira número. Qualquer chave
# ou valor fora disso invalida o conjunto inteiro: a jogada não guarda hash arbitrário.
module Autonomia::Prospecting::SavedPresetFilters
  YES_NO = %w[yes no].freeze
  YES_ONLY = %w[yes].freeze
  # A busca pagina até a 60ª posição (SearchRunner::MAX_REQUESTED_LIMIT); "fora do top N" deixa ao menos uma.
  RULES = {
    'has_website' => { choices: YES_NO },
    'has_phone' => { choices: YES_NO },
    'has_photos' => { choices: YES_NO },
    'open_now' => { choices: YES_ONLY },
    'has_opening_hours' => { choices: YES_ONLY },
    'rating_min' => { range: 0..5 },
    'rating_max' => { range: 0..5 },
    'reviews_min' => { range: 0..10_000, integer: true },
    'outside_top' => { range: 1..59, integer: true },
    'search_rank_max' => { range: 1..60, integer: true }
  }.freeze

  INVALID = Object.new.freeze

  # Devolve o hash normalizado, ou nil quando algo não segue as regras.
  def self.normalize(raw)
    return unless raw.is_a?(Hash)

    pairs = raw.map { |key, value| [key.to_s, entry(key.to_s, value)] }
    return if pairs.any? { |_key, value| value.equal?(INVALID) }

    normalized = pairs.to_h.compact
    rating_order_valid?(normalized) ? normalized : nil
  end

  # Valor normalizado, nil para filtro vazio (sai do hash) ou INVALID.
  def self.entry(key, value)
    rule = RULES[key]
    return INVALID if rule.nil?
    return if value.nil? || value == ''

    parsed = rule[:choices] ? choice(value, rule) : number(value, rule)
    parsed.nil? ? INVALID : parsed
  end

  def self.choice(value, rule)
    rule[:choices].include?(value) ? value : nil
  end

  def self.number(value, rule)
    number = number_from(value)
    return if number.nil? || !rule[:range].cover?(number)

    whole = number == number.floor
    return if rule[:integer] && !whole

    whole ? number.to_i : number
  end

  def self.number_from(value)
    return unless value.is_a?(String) || value.is_a?(Numeric)

    number = Float(value.to_s.strip, exception: false)
    number&.finite? ? number : nil
  end

  def self.rating_order_valid?(filters)
    return true unless filters.key?('rating_min') && filters.key?('rating_max')

    filters['rating_min'] <= filters['rating_max']
  end

  private_class_method :entry, :choice, :number, :number_from, :rating_order_valid?
end
