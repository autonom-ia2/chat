# #2863 — a profundidade do título pela numeração no começo dele, para o nível entre títulos da mesma letra e da mesma
# fonte (incluído em Processors::PdfBlocos). Lê só a forma do primeiro pedaço do título, nunca as palavras:
# - sem número ("CLÁUSULA 2 – …", "COBERTURA ADICIONAL DE …"): 0, acima dos numerados;
# - número com pontos ("1.", "1.3.", "1.3.1."): quantos números tem (1, 2, 3…);
# - marcador de item curto fechado por parêntese ("a)", "1)"): abaixo de qualquer número.
module Autonomia::Agents::Knowledge::Processors::PdfBlocos::Numeracao
  # O marcador de item tem até MARCADOR caracteres com o parêntese ("a)", "iv)").
  MARCADOR = 4
  ITEM = 1_000
  DIGITOS = ('0'..'9')

  def self.profundidade(texto)
    primeiro = texto.to_s.split.first.to_s
    return ITEM if marcador?(primeiro)

    numeros = primeiro.split('.')
    numeros.any? && numeros.all? { |numero| numero?(numero) } ? numeros.size : 0
  end

  def self.marcador?(pedaco)
    pedaco.length.between?(2, MARCADOR) && pedaco.end_with?(')')
  end

  def self.numero?(pedaco)
    !pedaco.empty? && pedaco.each_char.all? { |letra| DIGITOS.cover?(letra) }
  end
end
