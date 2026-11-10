# #2863 — a profundidade do título pela numeração no começo dele, para o nível entre títulos da mesma letra (chamado pelo
# nome em Processors::PdfBlocos#com_niveis). Lê só a forma do primeiro pedaço do título, nunca as palavras:
# - sem número ("CLÁUSULA 2 – …", "COBERTURA ADICIONAL DE …"): 0, acima dos numerados quando abre uma numeração
#   (profundidades);
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

  # A profundidade de cada título, na ordem do documento. O título sem número fica acima dos numerados (0) só quando
  # abre uma numeração (abre_numeracao?). No meio da seção (um rótulo entre "2.1." e "2.2.", ou antes do "3."), fica na
  # profundidade do último numerado, irmão dele, para não virar pai das seções seguintes.
  def self.profundidades(textos)
    numeros = textos.map { |texto| primeiro_numero(texto) }
    ultimo = nil
    textos.each_with_index.map do |texto, indice|
      profundidade = profundidade(texto)
      profundidade = ultimo[:profundidade] if profundidade.zero? && ultimo && !abre_numeracao?(textos[indice + 1], numeros[indice + 1], ultimo)
      ultimo = { profundidade: profundidade, numero: numeros[indice] } if numeros[indice]
      profundidade
    end
  end

  # Abre numeração: o seguinte é o "1." ou é mais fundo com outro primeiro número ("CLÁUSULA 3" antes do "3.1."). O
  # seguinte que só continua a sequência ("3." depois de "2.1.") não abre. Sem título seguinte (fim do documento, um
  # "ANEXO I"), o título sem número fica no topo.
  def self.abre_numeracao?(seguinte, numero, ultimo)
    return true if seguinte.nil?
    return false if numero.nil?

    profundidade(seguinte) == 1 ? numero == '1' : numero != ultimo[:numero]
  end

  # O primeiro número do título numerado ("2" de "2.1."); nil sem número ou com marcador de item.
  def self.primeiro_numero(texto)
    return unless profundidade(texto).between?(1, ITEM - 1)

    texto.split.first.split('.').first
  end

  # #2865 — o título de baixo é filho do de cima pela numeração: o de cima não tem número e o de baixo é o primeiro filho
  # de uma numeração ("CLÁUSULA 4" sobre "4.1.", "COBERTURA" sobre "1."), ou a numeração de baixo continua a de cima ("4."
  # sobre "4.4."). Itens irmãos ("1." e "2."), numerações sem relação ("2." sobre "4.5.") e item sem número sobre um
  # número qualquer ("- Raio;" sobre "4.5.") não são.
  def self.filho?(de_cima, de_baixo)
    acima = profundidade(de_cima)
    return false if acima == ITEM || !primeiro_numero(de_baixo)

    numeros_de_baixo = de_baixo.split.first.split('.')
    return numeros_de_baixo.last == '1' if acima.zero?

    numeros_de_cima = de_cima.split.first.split('.')
    numeros_de_baixo.size > numeros_de_cima.size && numeros_de_baixo.first(numeros_de_cima.size) == numeros_de_cima
  end

  def self.marcador?(pedaco)
    pedaco.length.between?(2, MARCADOR) && pedaco.end_with?(')')
  end

  def self.numero?(pedaco)
    !pedaco.empty? && pedaco.each_char.all? { |letra| DIGITOS.cover?(letra) }
  end
end
