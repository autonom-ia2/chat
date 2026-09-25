# Nota e prioridade do Orth para os leads de uma busca (#681, frente A). Pura: não lê nem grava banco. A coorte do
# rating e do volume híbridos é o próprio conjunto passado, então quem chama passa todos os leads da busca de uma vez.
#
# leads: hashes com os atributos que o lead já tem (website, phone, rating, reviews_count, photo_count ou has_photos,
#   reviews com publishTime ou o raw_payload do Google, open_now, search_rank) e, para a prioridade, os de contato
#   (whatsapp_verified, decisor_found, decisor_failed, already_in_crm, crm_funnel_name, recently_contacted,
#   days_since_last_contact).
# mode: 'gbp' ou 'general'. weights: os 6 componentes do Orth (nil = padrão do Orth; ver WeightMapping para os 8 sinais
#   de hoje). filters: os advanced_filters da busca.
class Autonomia::Prospecting::Scoring::OrthScorer
  MODES = %w[gbp general].freeze
  OPEN_NOW_FILTER_VALUES = [true, 'yes'].freeze

  Result = Data.define(
    :score, :priority_score, :priority_position, :components, :negative_factors, :negative_penalty, :human_insight,
    :effective_weights, :confidence_flags, :traction_multiplier, :priority_factors
  )

  def initialize(leads:, mode:, weights:, filters:, reference_time: Time.current)
    raise ArgumentError, "unknown score mode: #{mode.inspect}" unless MODES.include?(mode)

    @signals = leads.map { |lead| Autonomia::Prospecting::Scoring::LeadSignals.from(lead) }
    @mode = mode
    @weights = weights
    @filters = filters.to_h.stringify_keys
    @reference_time = reference_time
  end

  def perform
    breakdowns = @signals.map { |signals| breakdown(signals) }
    negatives = @signals.map { |signals| Autonomia::Prospecting::Scoring::NegativeFactors.call(signals, reference_time: @reference_time) }
    priorities = Autonomia::Prospecting::Scoring::Priority.rank(priority_inputs(breakdowns, negatives))

    breakdowns.each_with_index.map { |breakdown, index| result(breakdown, negatives[index], priorities[index]) }
  end

  private

  def breakdown(signals)
    Autonomia::Prospecting::Scoring::ComponentScore.new(signals, context).perform
  end

  def context
    @context ||= Autonomia::Prospecting::Scoring::ComponentScore::Context.new(
      mode: @mode, weights: @weights, filters: @filters, reference_time: @reference_time,
      rating_cohort: Autonomia::Prospecting::Scoring::Cohort.rating(@signals.map(&:rating)),
      volume_cohort: Autonomia::Prospecting::Scoring::Cohort.volume(@signals.map(&:reviews_count))
    )
  end

  def priority_inputs(breakdowns, negatives)
    open_now_filter_active = OPEN_NOW_FILTER_VALUES.include?(@filters['open_now'])
    @signals.each_with_index.map do |signals, index|
      { base_score: breakdowns[index].total, signals: signals, negative_penalty: negatives[index][:total_penalty],
        open_now_filter_active: open_now_filter_active }
    end
  end

  def result(breakdown, negative, priority)
    Result.new(
      score: breakdown.total,
      priority_score: priority[:priority_score],
      priority_position: priority[:priority_position],
      components: breakdown.components,
      negative_factors: negative[:factors].pluck('key'),
      negative_penalty: negative[:total_penalty],
      human_insight: Autonomia::Prospecting::Scoring::HumanInsight.build(total: breakdown.total, mode: @mode, components: breakdown.components),
      effective_weights: breakdown.effective_weights,
      confidence_flags: breakdown.confidence_flags,
      traction_multiplier: breakdown.traction_multiplier,
      priority_factors: priority[:factors]
    )
  end
end
