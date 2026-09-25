# Normalização de texto dos cadastros públicos (porte de normalization.ts do Orth, #679): maiúsculas, sem acento,
# tudo que não é letra ou dígito vira espaço, espaços colapsados. Serve para comparar qualificação, natureza jurídica e
# situação cadastral contra tabela fechada. Sem regex, de propósito (regra do Rodrigo, 20/09/2026).
module Autonomia::Prospecting::Research::Normalization
  KEY_CHARS = (('A'..'Z').to_a + ('0'..'9').to_a).to_set.freeze
  DIGITS = ('0'..'9').to_set.freeze

  module_function

  def key(value)
    ActiveSupport::Inflector.transliterate(value.to_s).upcase.each_char.map { |char| KEY_CHARS.include?(char) ? char : ' ' }.join.split.join(' ')
  end

  def digits(value)
    value.to_s.each_char.select { |char| DIGITS.include?(char) }.join
  end

  # Números inteiros na ordem em que aparecem ("Entre 13 a 20 anos" -> [13, 20]).
  def numbers(value)
    value.to_s.each_char.map { |char| DIGITS.include?(char) ? char : ' ' }.join.split.map(&:to_i)
  end

  # Texto aparado, com espaços colapsados, ou nil quando vazio.
  def text(value)
    return nil unless value.is_a?(String)

    squished = value.split.join(' ')
    squished.presence
  end
end
