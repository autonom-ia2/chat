# Penalidades que descem a prioridade de um lead (porte de computeNegativeFactors do negative-factors.ts do Orth, #681).
# Já no CRM e contato recente dependem de quem chama preencher o lead; avaliação velha e nota baixa com poucas
# avaliações vêm dos dados do Google. O total é positivo e sai da prioridade bruta, não da nota.
module Autonomia::Prospecting::Scoring::NegativeFactors
  PENALTIES = {
    'already_in_crm' => 40,
    'recently_contacted' => 20,
    'old_reviews' => 10,
    'low_rating_low_volume' => 15
  }.freeze
  OLD_REVIEW_DAYS = 2 * 365
  DAYS_PER_YEAR = 365
  SECONDS_PER_DAY = 86_400
  LOW_RATING = 2.0
  LOW_VOLUME = 5
  I18N_SCOPE = 'autonomia.prospecting.scoring.negative_factors'.freeze

  module_function

  def call(signals, reference_time:)
    factors = [crm_factor(signals), old_reviews_factor(signals, reference_time), low_rating_factor(signals)].compact
    { total_penalty: factors.sum { |factor| factor['points'].abs }, factors: factors }
  end

  # Contato recente não soma com já no CRM: é o mesmo motivo contado duas vezes.
  def crm_factor(signals)
    return factor('already_in_crm', crm_reason(signals.crm_funnel_name)) if signals.already_in_crm
    return unless signals.recently_contacted

    factor('recently_contacted', contact_reason(signals.days_since_last_contact))
  end

  def crm_reason(funnel_name)
    funnel_name ? translate('already_in_funnel', name: funnel_name) : translate('already_in_crm')
  end

  def contact_reason(days)
    days.is_a?(Integer) ? translate('contacted_days_ago', days: days) : translate('contacted_recently')
  end

  def old_reviews_factor(signals, reference_time)
    latest = signals.latest_review_time
    return unless latest

    age_seconds = reference_time - latest
    return unless age_seconds > OLD_REVIEW_DAYS * SECONDS_PER_DAY

    factor('old_reviews', translate('old_reviews', count: (age_seconds / (DAYS_PER_YEAR * SECONDS_PER_DAY)).floor))
  end

  def low_rating_factor(signals)
    rating = signals.rating
    count = signals.reviews_count
    return unless rating && count && rating < LOW_RATING && count.positive? && count < LOW_VOLUME

    factor('low_rating_low_volume', translate('low_rating_low_volume', rating: format('%.1f', rating), count: count))
  end

  def factor(key, reason)
    { 'key' => key, 'points' => -PENALTIES.fetch(key), 'reason' => reason }
  end

  def translate(key, **)
    I18n.t(key, scope: I18N_SCOPE, **)
  end
end
