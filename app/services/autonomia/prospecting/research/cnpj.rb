# CNPJ com dígito verificador (porte do validateCnpj do Orth, #679). Só dígitos contam: a pontuação some com
# String#delete, sem regex. CNPJ com os 14 dígitos iguais é recusado, como no Orth.
module Autonomia::Prospecting::Research::Cnpj
  LENGTH = 14
  FIRST_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
  SECOND_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze

  module_function

  def digits(value)
    value.to_s.delete('^0-9')
  end

  def valid?(value)
    return false unless value.is_a?(String) && value.length == LENGTH && value.delete('0-9').empty?
    return false if value.chars.uniq.one?

    first = check_digit(value[0, 12], FIRST_WEIGHTS)
    second = check_digit("#{value[0, 12]}#{first}", SECOND_WEIGHTS)
    value.end_with?("#{first}#{second}")
  end

  # Devolve os 14 dígitos do CNPJ válido, ou nil.
  def normalize(value)
    candidate = digits(value)
    valid?(candidate) ? candidate : nil
  end

  def check_digit(base, weights)
    remainder = weights.each_with_index.sum { |weight, index| base[index].to_i * weight } % 11
    remainder < 2 ? 0 : 11 - remainder
  end
end
