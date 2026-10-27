# Valor que é e-mail ou telefone (#858, decisão do Rodrigo em 03/10/2026: e-mail e telefone nunca vão ao Jev, nem
# disfarçados de nome ou de atributo). Sem regex: só a forma do valor. Usado pelo Decisor (Autonomia::Decisores::Estado)
# e pelo card de lead do formulário da Meta (#2195), cujo título vai à IA e a quem não vê o contato.
module Autonomia::DadoDeContato
  SIMBOLOS_DE_TELEFONE = [' ', '+', '-', '(', ')', '.'].freeze
  MIN_DIGITOS_TELEFONE = 8

  module_function

  def contato?(valor)
    email?(valor) || telefone?(valor)
  end

  # Só dígitos e os símbolos de um número formatado, com dígitos de telefone. Data (1980-05-17) não conta.
  def telefone?(valor)
    return false unless valor.is_a?(String) || valor.is_a?(Integer)

    texto = valor.to_s.strip
    !data?(texto) && texto.each_char.count { |letra| digito?(letra) } >= MIN_DIGITOS_TELEFONE && so_telefone?(texto)
  end

  def email?(valor)
    return false unless valor.is_a?(String)

    usuario, dominio = valor.strip.split('@', 2)
    valor.count('@') == 1 && valor.strip.exclude?(' ') && usuario.present? && dominio.to_s.include?('.')
  end

  def so_telefone?(texto)
    texto.each_char.all? { |letra| digito?(letra) || SIMBOLOS_DE_TELEFONE.include?(letra) }
  end

  def digito?(letra)
    letra.between?('0', '9')
  end

  def data?(texto)
    texto.length == 10 && texto[4] == '-' && texto[7] == '-'
  end
end
