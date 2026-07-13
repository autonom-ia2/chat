class Autonomia::Prospecting::LeadScorer
  SIGNAL_KEYS = Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.keys.freeze

  def initialize(lead_attributes:, query:, google_rank:, weights:, score_mode: 'gbp')
    @lead_attributes = lead_attributes.symbolize_keys
    @query = query.to_s.downcase
    @google_rank = google_rank.to_i
    @score_mode = %w[gbp general].include?(score_mode.to_s) ? score_mode.to_s : 'gbp'
    @weights = Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS
                                                        .merge(weights.to_h.slice(*SIGNAL_KEYS))
                                                        .transform_values(&:to_f)
  end

  def perform
    normalized = normalized_weights
    signals = signal_scores
    score = normalized.sum { |key, weight| signals[key].to_f * weight }.round(2)
    score = [[score, 0].max, 100].min

    {
      score: score,
      priority_score: score,
      score_breakdown: SIGNAL_KEYS.index_with do |key|
        {
          'signal' => signals[key].round(2),
          'weight' => @weights[key].round(2),
          'weighted_score' => (signals[key] * normalized[key]).round(2)
        }
      end.merge(
        '_mode' => @score_mode,
        '_total' => score
      ),
      negative_factors: negative_factors(signals),
      human_insight: human_insight(score, signals)
    }
  end

  private

  def normalized_weights
    total = @weights.values.sum
    return SIGNAL_KEYS.index_with { 0.0 } if total <= 0

    SIGNAL_KEYS.index_with { |key| @weights[key].to_f / total }
  end

  def signal_scores
    {
      'rating' => rating_score,
      'reviews_count' => reviews_score,
      'website' => presence_score(:website),
      'phone' => presence_score(:phone),
      'activity' => activity_score,
      'photos' => photos_score,
      'google_rank' => rank_score,
      'query_relevance' => query_relevance_score
    }
  end

  def rating_score
    rating = @lead_attributes[:rating].to_f
    if gbp_mode?
      return 90.0 if rating <= 0
      return 100.0 if rating < 3.0
      return 80.0 if rating < 3.5
      return 55.0 if rating < 4.0
      return 25.0 if rating < 4.5

      return 5.0
    end

    return 0.0 if rating <= 0

    (rating / 5.0 * 100).clamp(0, 100)
  end

  def reviews_score
    reviews = @lead_attributes[:reviews_count].to_i
    if gbp_mode?
      return 100.0 if reviews <= 0
      return 90.0 if reviews < 5
      return 65.0 if reviews < 20
      return 35.0 if reviews < 50
      return 15.0 if reviews < 200

      return 0.0
    end

    return 0.0 if reviews <= 0

    [[Math.log10(reviews + 1) / Math.log10(501) * 100, 100].min, 0].max
  end

  def presence_score(attribute)
    present = @lead_attributes[attribute].present?
    gbp_mode? ? (present ? 0.0 : 100.0) : (present ? 100.0 : 0.0)
  end

  def rank_score
    return 0.0 if @google_rank <= 0

    [[100 - ((@google_rank - 1) * 5), 0].max, 100].min
  end

  def photos_score
    photos_count = Array(raw_payload['photos']).size
    if gbp_mode?
      return 100.0 if photos_count.zero?
      return 70.0 if photos_count < 3
      return 35.0 if photos_count < 10

      return 0.0
    end

    return 0.0 if photos_count.zero?

    [[photos_count / 10.0 * 100, 100].min, 0].max
  end

  def activity_score
    latest_review_time = review_publish_times.max
    if gbp_mode?
      return 100.0 if latest_review_time.blank?

      days = ((Time.current - latest_review_time) / 1.day).floor
      return 0.0 if days <= 30
      return 20.0 if days <= 90
      return 50.0 if days <= 180
      return 75.0 if days <= 365

      return 100.0
    end

    return 0.0 if latest_review_time.blank?

    days = ((Time.current - latest_review_time) / 1.day).floor
    return 100.0 if days <= 30
    return 80.0 if days <= 90
    return 50.0 if days <= 180
    return 25.0 if days <= 365

    0.0
  end

  def query_relevance_score
    name = @lead_attributes[:name].to_s.downcase
    category = @lead_attributes[:category].to_s.downcase
    query_terms = @query.split(/\s+/).reject { |term| term.length < 3 }
    return 50.0 if query_terms.blank?

    matches = query_terms.count { |term| name.include?(term) || category.include?(term) }
    (matches.to_f / query_terms.size * 100).clamp(0, 100)
  end

  def negative_factors(signals)
    [].tap do |factors|
      factors << 'missing_website' if @lead_attributes[:website].blank?
      factors << 'missing_phone' if @lead_attributes[:phone].blank?
      rating = @lead_attributes[:rating].to_f
      factors << 'low_rating' if rating.positive? && rating < 3.5
      factors << 'low_reviews' if @lead_attributes[:reviews_count].to_i < 10
      factors << 'missing_photos' if Array(raw_payload['photos']).blank?
      factors << 'inactive_gbp' if gbp_mode? && signals['activity'] >= 75
    end
  end

  def human_insight(score, signals)
    if gbp_mode?
      return 'Oportunidade GMN alta: perfil com lacunas claras para presença digital.' if score >= 80
      return 'Boa oportunidade GMN: há sinais de melhoria em reputação, presença ou atividade.' if score >= 60
      return 'Oportunidade GMN moderada; valide se a lacuna combina com a oferta.' if score >= 35

      return 'Perfil GMN mais completo; menor prioridade para oferta de presença digital.'
    end

    return 'Lead prioritário: boa reputação e dados de contato completos.' if score >= 80
    return 'Boa oportunidade, mas vale revisar sinais de contato e reputação.' if score >= 60
    return 'Lead com sinais incompletos; priorize após validação manual.' if signals['website'].zero? || signals['phone'].zero?

    'Lead de baixa prioridade para abordagem inicial.'
  end

  def gbp_mode?
    @score_mode == 'gbp'
  end

  def raw_payload
    @raw_payload ||= @lead_attributes[:raw_payload].to_h
  end

  def review_publish_times
    Array(raw_payload['reviews']).filter_map do |review|
      value = review['publishTime'] || review[:publishTime]
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end
  end
end
