# Coorte da busca para o rating e o volume híbridos do modo GMN (porte de computeRatingCohortStats e
# computeVolumeCohortStats do score.ts do Orth, #681). O relativo só liga com 5 leads ou mais e amplitude suficiente:
# 0.2 de nota, 0.4 em ln(1 + avaliações).
module Autonomia::Prospecting::Scoring::Cohort
  Rating = Data.define(:rated_lead_count, :r_min, :r_max, :relative_enabled)
  Volume = Data.define(:valid_count_lead_count, :min_log, :max_log, :relative_enabled)

  MIN_LEADS = 5
  MIN_RATING_SPAN = 0.2
  MIN_VOLUME_LOG_SPAN = 0.4
  EMPTY_RATING = Rating.new(rated_lead_count: 0, r_min: nil, r_max: nil, relative_enabled: false)
  EMPTY_VOLUME = Volume.new(valid_count_lead_count: 0, min_log: nil, max_log: nil, relative_enabled: false)

  module_function

  def rating(ratings)
    valid = ratings.select { |value| value.is_a?(Numeric) && value.to_f.finite? }
    return EMPTY_RATING if valid.empty?

    r_min, r_max = valid.minmax
    Rating.new(rated_lead_count: valid.size, r_min: r_min, r_max: r_max,
               relative_enabled: valid.size >= MIN_LEADS && (r_max - r_min) >= MIN_RATING_SPAN)
  end

  # Zero avaliação conta; ausente (nil) não.
  def volume(counts)
    logs = counts.select { |value| value.is_a?(Numeric) && value >= 0 }.map { |value| Math.log(1 + value) }
    return EMPTY_VOLUME if logs.empty?

    min_log, max_log = logs.minmax
    Volume.new(valid_count_lead_count: logs.size, min_log: min_log, max_log: max_log,
               relative_enabled: logs.size >= MIN_LEADS && (max_log - min_log) >= MIN_VOLUME_LOG_SPAN)
  end
end
