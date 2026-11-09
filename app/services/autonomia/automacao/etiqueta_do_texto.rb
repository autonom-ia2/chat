# G29 (#2702): um texto da receita (o nome do anúncio do formulário) vira etiqueta. Nome real de anúncio tem espaço,
# vírgula, aspas e "%" ("Black Friday, 50% off"), e a etiqueta só aceita o que a tela de etiquetas aceita (Label:
# letras, inclusive acentuadas, números, "-" e "_", duas no mínimo, em minúsculas). O resto vira "_", sem "_" repetido
# nem nas pontas: "black_friday_50_off". O texto original fica na descrição da etiqueta (PassoDeAcao).
#
# Devolve nil quando não sobra etiqueta que o Label aceite ("%%", uma letra só): o passo pula com o motivo.
module Autonomia::Automacao::EtiquetaDoTexto
  SEPARADOR = '_'.freeze
  PERMITIDOS = ['-', SEPARADOR].freeze
  TAMANHO_MAXIMO = 255

  module_function

  def de(texto)
    etiqueta = aparar(trocar_o_que_nao_cabe(texto.to_s.downcase).first(TAMANHO_MAXIMO))
    etiqueta if RegexHelper::UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE.match?(etiqueta)
  end

  def trocar_o_que_nao_cabe(texto)
    texto.each_char.map { |letra| cabe?(letra) ? letra : SEPARADOR }.join.split(SEPARADOR).reject(&:empty?).join(SEPARADOR)
  end

  # Letra com maiúscula e minúscula (o "ç" e o "ã" também), algarismo, "-" ou "_".
  def cabe?(letra)
    letra.upcase != letra.downcase || letra.between?('0', '9') || PERMITIDOS.include?(letra)
  end

  def aparar(etiqueta)
    etiqueta = etiqueta[1..] while etiqueta.start_with?(*PERMITIDOS)
    etiqueta = etiqueta[..-2] while etiqueta.end_with?(*PERMITIDOS)
    etiqueta
  end
end
