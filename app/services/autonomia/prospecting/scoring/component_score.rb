# Nota de 0 a 100 de um lead pelos 6 componentes do Orth (porte de computeScore do score.ts, #681). Os pesos passam
# pelos filtros ativos (EffectiveWeights); a soma dos pontos multiplica pela tração da posição no Google, só no GMN.
class Autonomia::Prospecting::Scoring::ComponentScore
  Breakdown = Data.define(:total, :components, :confidence_flags, :traction_multiplier, :mode, :effective_weights) do
    def component(key)
      components.find { |item| item['key'] == key }
    end
  end

  # O que vale para todos os leads da busca: modo, pesos, filtros, coortes e o instante de referência da atividade.
  Context = Data.define(:mode, :weights, :filters, :rating_cohort, :volume_cohort, :reference_time)

  FACTORS = Autonomia::Prospecting::Scoring::Factors
  TRACTION_BANDS = [[5, 1.5], [10, 1.3], [20, 1.1], [40, 0.9]].freeze
  TRACTION_OUTSIDE = 0.7
  TRACTION_NEUTRAL = 1.0

  def self.gbp_activity_factor(age_days)
    FACTORS.gbp_activity_factor(age_days)
  end

  def initialize(signals, context)
    @signals = signals
    @mode = context.mode
    @weights = context.weights
    @filters = context.filters
    @rating_cohort = context.rating_cohort
    @volume_cohort = context.volume_cohort
    @reference_time = context.reference_time
  end

  def perform
    weights = Autonomia::Prospecting::Scoring::EffectiveWeights.for(@weights, @filters)
    results = general? ? general_factors : gbp_factors
    components = results.map { |key, factor| component(key, weights.fetch(key), factor) }
    multiplier = traction_multiplier

    Breakdown.new(
      total: (components.sum { |item| item['points'] } * multiplier).round.clamp(0, 100),
      components: components,
      confidence_flags: results.select { |_key, factor| factor[:weak_signal] }.keys,
      traction_multiplier: multiplier,
      mode: @mode,
      effective_weights: weights
    )
  end

  private

  def general?
    @mode == 'general'
  end

  def component(key, weight, factor)
    {
      'key' => key,
      'weight' => weight,
      'value' => factor[:factor],
      'points' => weight * factor[:factor],
      'audit' => { 'reason' => factor[:reason], 'weak_signal' => factor[:weak_signal] }.merge(factor[:audit])
    }
  end

  def gbp_factors
    {
      'website' => presence(@signals.website?, 'site', present_factor: 0),
      'phone' => presence(@signals.phone?, 'telefone', present_factor: 0),
      'rating' => FACTORS.gbp_rating(@signals.rating, @signals.reviews_count, @rating_cohort),
      'volume' => FACTORS.gbp_volume(@signals.reviews_count, @volume_cohort),
      'activity' => FACTORS.gbp_activity(@signals, @reference_time),
      'photos' => FACTORS.gbp_photos(@signals.photo_count)
    }
  end

  def general_factors
    {
      'website' => presence(@signals.website?, 'site', present_factor: 1),
      'phone' => presence(@signals.phone?, 'telefone', present_factor: 1),
      'rating' => FACTORS.general_rating(@signals.rating),
      'volume' => FACTORS.general_volume(@signals.reviews_count),
      'activity' => FACTORS.general_activity(@signals.reviews_count),
      'photos' => FACTORS.general_photos(@signals.photo_count)
    }
  end

  def presence(present, label, present_factor:)
    FACTORS.result(present ? present_factor : 1 - present_factor, present ? "tem #{label}" : "sem #{label}")
  end

  # Posição alta no Google: o dono já acredita no Google e fecha mais fácil. No Geral a posição não conta.
  def traction_multiplier
    return TRACTION_NEUTRAL if general? || @signals.search_rank.nil?

    TRACTION_BANDS.find { |limit, _factor| @signals.search_rank <= limit }&.last || TRACTION_OUTSIDE
  end
end
