# Fator de 0 a 1 de cada componente, por modo (porte das funções f* do score.ts do Orth, #681). No GMN, fator alto é
# lacuna (oportunidade); no Geral, é perfil estruturado. Rating e volume do GMN misturam 70% absoluto com 30% relativo à
# coorte da busca quando ela permite. Cada função devolve o fator, o motivo e a auditoria que o Orth grava.
module Autonomia::Prospecting::Scoring::Factors
  LN201 = Math.log(201)
  SECONDS_PER_DAY = 86_400
  ABSOLUTE_SHARE = 0.7
  RELATIVE_SHARE = 0.3
  GBP_ACTIVITY_BANDS = [[7, 0], [30, 0.15], [60, 0.3], [120, 0.55], [180, 0.75], [365, 0.9]].freeze
  GBP_PHOTO_BANDS = [[15, 0, 'muitas fotos'], [10, 0.15, 'fotos suficientes'], [5, 0.35, 'poucas fotos'],
                     [3, 0.55, 'muito poucas fotos'], [1, 0.8, 'quase sem fotos']].freeze
  GENERAL_PHOTO_BANDS = [[15, 1, 'muitas fotos', false], [10, 0.8, 'fotos suficientes', false], [5, 0.55, 'poucas fotos', false],
                         [3, 0.3, 'muito poucas fotos', false], [1, 0.1, 'quase sem fotos', true]].freeze
  GENERAL_RATING_BANDS = [[4.5, 1, 'rating excelente'], [4.0, 0.8, 'rating bom'], [3.5, 0.55, 'rating médio'],
                          [3.0, 0.3, 'rating baixo']].freeze
  GENERAL_VOLUME_BANDS = [[100, 1, 'muitos reviews'], [50, 0.8, 'reviews suficientes'], [20, 0.55, 'poucos reviews'],
                          [5, 0.3, 'muito poucos reviews']].freeze
  GENERAL_ACTIVITY_BANDS = [[50, 1, 'negócio muito ativo', false], [20, 0.75, 'negócio ativo', false],
                            [5, 0.45, 'atividade moderada', true], [1, 0.2, 'pouco ativo', true]].freeze

  module_function

  def result(factor, reason, weak_signal: false, audit: {})
    { factor: factor, reason: reason, weak_signal: weak_signal, audit: audit }
  end

  def gbp_rating(rating, reviews_count, cohort)
    return gbp_rating_missing(reviews_count) if rating.nil?

    absolute = ((5.0 - rating) / 4.0).clamp(0.0, 1.0)
    relative = relative_factor(cohort.relative_enabled, cohort.r_min, cohort.r_max, rating)
    final = relative ? (ABSOLUTE_SHARE * absolute) + (RELATIVE_SHARE * relative) : absolute
    audit = { 'final_factor' => final, 'absolute_factor' => absolute, 'relative_factor' => relative,
              'relative_enabled' => cohort.relative_enabled }.compact
    result(final, 'GMN rating híbrido', audit: { 'rating' => audit })
  end

  def gbp_rating_missing(reviews_count)
    factor = missing_rating_factor(reviews_count)
    result(factor, 'GMN rating: sem rating', audit: { 'rating' => { 'final_factor' => factor, 'relative_enabled' => false } })
  end

  def missing_rating_factor(reviews_count)
    return 1.0 if reviews_count.nil? || reviews_count.zero?

    reviews_count < 5 ? 0.9 : 0.75
  end

  # Contagem ausente (nil) é sinal fraco; zero avaliação é valor válido e segue a conta.
  def gbp_volume(count, cohort)
    return gbp_volume_missing if count.nil? || count.negative?

    absolute = 1 - (Math.log(1 + [count, 200].min) / LN201)
    relative = relative_factor(cohort.relative_enabled, cohort.min_log, cohort.max_log, Math.log(1 + count))
    final = relative ? (ABSOLUTE_SHARE * absolute) + (RELATIVE_SHARE * relative) : absolute
    audit = { 'final_factor' => final, 'absolute_factor' => absolute, 'relative_factor' => relative,
              'relative_enabled' => cohort.relative_enabled }.compact
    result(final, 'GMN volume híbrido', audit: { 'volume' => audit })
  end

  # Posição do valor na coorte, invertida: o maior da coorte vale 0, o menor vale 1.
  def relative_factor(enabled, low, high, value)
    return unless enabled && low && high && high > low

    ((high - value) / (high - low)).clamp(0.0, 1.0)
  end

  def gbp_volume_missing
    result(0.9, 'GMN volume: contagem ausente', weak_signal: true, audit: { 'volume' => { 'final_factor' => 0.9, 'relative_enabled' => false } })
  end

  # Frescor pela avaliação mais recente: sem avaliação vale 1; avaliação sem data que se leia vale 0.85 e é sinal fraco.
  def gbp_activity(signals, reference_time)
    return result(1, 'GMN activity: sem reviews', audit: { 'activity' => activity_audit(1, nil, nil, 'no_reviews') }) if signals.reviews.empty?

    latest = signals.latest_review_time
    if latest.nil?
      return result(0.85, 'GMN activity: reviews sem publishTime', weak_signal: true,
                                                                   audit: { 'activity' => activity_audit(0.85, nil, nil, 'no_publish_time') })
    end

    age_days = [((reference_time - latest) / SECONDS_PER_DAY).floor, 0].max
    factor = gbp_activity_factor(age_days)
    result(factor, "GMN activity: última review há #{age_days}d",
           audit: { 'activity' => activity_audit(factor, age_days, latest.utc.iso8601, 'ok') })
  end

  def activity_audit(factor, age_days, latest, audit_case)
    { 'final_factor' => factor, 'age_days' => age_days, 'latest_publish_time' => latest, 'case' => audit_case }
  end

  def gbp_activity_factor(age_days)
    GBP_ACTIVITY_BANDS.find { |limit, _factor| age_days <= limit }&.last || 1
  end

  def gbp_photos(count)
    band = GBP_PHOTO_BANDS.find { |minimum, _factor, _reason| count >= minimum }
    band ? result(band[1], band[2]) : result(1, 'sem fotos', weak_signal: true)
  end

  def general_photos(count)
    band = GENERAL_PHOTO_BANDS.find { |minimum, _factor, _reason, _weak| count >= minimum }
    band ? result(band[1], band[2], weak_signal: band[3]) : result(0, 'sem fotos', weak_signal: true)
  end

  def general_rating(rating)
    return result(0, 'sem rating') if rating.nil?

    band = GENERAL_RATING_BANDS.find { |minimum, _factor, _reason| rating >= minimum }
    band ? result(band[1], band[2]) : result(0.1, 'rating muito baixo')
  end

  def general_volume(count)
    return result(0, 'sem reviews') if count.nil?

    band = GENERAL_VOLUME_BANDS.find { |minimum, _factor, _reason| count >= minimum }
    band ? result(band[1], band[2]) : result(0.1, 'quase sem reviews')
  end

  def general_activity(count)
    band = GENERAL_ACTIVITY_BANDS.find { |minimum, _factor, _reason, _weak| count.to_i >= minimum }
    band ? result(band[1], band[2], weak_signal: band[3]) : result(0, 'sem atividade registrada', weak_signal: true)
  end
end
