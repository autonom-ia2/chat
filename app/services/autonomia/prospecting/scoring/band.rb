# Faixa da prioridade (#681): as quatro do card (prospectingPriority.js), com os limites do Orth (priority-utils.tsx):
# 75 ou mais, 50 ou mais, 25 ou mais, e o resto. A prioridade é arredondada antes, como no anel do card.
module Autonomia::Prospecting::Scoring::Band
  LIMITS = [[75, 'very_hot'], [50, 'high'], [25, 'warm']].freeze
  LOWEST = 'low'.freeze
  # Da mais quente para a mais fria, como o card lista.
  CODES = [*LIMITS.map(&:last), LOWEST].freeze

  module_function

  def code(priority)
    return if priority.nil?

    rounded = priority.to_f.round
    LIMITS.find { |limit, _code| rounded >= limit }&.last || LOWEST
  end

  # Altura da faixa: 0 na mais fria, 3 na mais quente. Subir de faixa é a altura crescer.
  def rank(code)
    CODES.size - 1 - CODES.index(code)
  end

  def label(code)
    return if code.blank?

    I18n.t("autonomia.prospecting.score_bands.#{code}")
  end
end
