# Telefone mascarado para a página pública do convite (#1190, J1-A2/RA-05): o cliente reconhece o próprio número
# sem que o link entregue o número inteiro a quem o abrir. Mostra o DDD (o que vem entre parênteses no formato
# nacional) e os 4 últimos dígitos: "+5511912345678" vira "(11) •••••-5678". Sem DDD, só os 4 últimos.
#
# O formato nacional vem da biblioteca de telefone do sistema (`TelephoneNumber`); a máscara anda caractere por
# caractere, sem regex.
class Crm::BookingV2::PhoneMask
  VISIBLE_TAIL = 4
  DOT = '•'.freeze
  DIGITS = '0123456789'.chars.freeze

  def self.mask(e164)
    return if e164.blank?

    parsed = TelephoneNumber.parse(e164.to_s)
    return unless parsed.valid?

    new(parsed.national_number(formatted: true)).to_s
  end

  def initialize(formatted)
    @formatted = formatted.to_s
  end

  def to_s
    total = formatted.chars.count { |char| digit?(char) }
    seen = 0
    formatted.chars.each_with_index.map do |char, index|
      next char unless digit?(char)

      seen += 1
      keep?(index, seen, total) ? char : DOT
    end.join
  end

  private

  attr_reader :formatted

  def keep?(index, seen, total)
    seen > total - VISIBLE_TAIL || (area_end.present? && index < area_end)
  end

  def area_end
    return @area_end if defined?(@area_end)

    @area_end = formatted.start_with?('(') ? formatted.index(')') : nil
  end

  def digit?(char)
    DIGITS.include?(char)
  end
end
