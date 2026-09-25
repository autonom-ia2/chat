# Faixa da prioridade (#681): as quatro do card (prospectingPriority.js), com os limites do Orth (priority-utils.tsx):
# 75 ou mais, 50 ou mais, 25 ou mais, e o resto. A prioridade é arredondada antes, como no anel do card.
module Autonomia::Prospecting::Scoring::Band
  LIMITS = [[75, 'very_hot'], [50, 'high'], [25, 'warm']].freeze
  LOWEST = 'low'.freeze

  module_function

  def code(priority)
    return if priority.nil?

    rounded = priority.to_f.round
    LIMITS.find { |limit, _code| rounded >= limit }&.last || LOWEST
  end

  def label(code)
    return if code.blank?

    I18n.t("autonomia.prospecting.score_bands.#{code}")
  end
end
