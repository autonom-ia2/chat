# QUAL SEGURADORA O CLIENTE QUIS DIZER — por comparação de texto, nunca por semelhança (entrega 8).
#
# O modelo entende a frase ("me manda a da Porto") e escreve o nome no parâmetro; o código só
# compara o que foi escrito com os nomes que o PORTAL deu às ofertas cotadas (o mapa que a cotação
# gravou em `InsuranceQuote::NOMES_KEY`). Comparação de dados: minúsculas, sem acento, sem espaço
# duplo — e nada além disso. Nenhuma distância de edição, nenhum sinônimo, nenhuma tabela nossa de
# nomes: o dia em que "Porto" casasse com "Porto Seguro Assinatura" por parecer, mandaríamos a
# proposta errada com cara de certa.
#
# A REGRA, para cada nome falado, contra os nomes cotados normalizados:
#   - o falado é PREFIXO de exatamente um nome cotado -> é esse ("porto" -> "Porto"; "bp a" ->
#     "Bp Assinatura"). O casamento exato é o caso particular do prefixo;
#   - é prefixo de mais de um -> AMBÍGUO, e a resposta lista as candidatas. É o caso real de "Bp":
#     no portal, 48 chama-se "Bp" e 55 "Bp Assinatura" (medido em 11/09/2026), e são produtos
#     diferentes — um total anual e uma assinatura mensal. Dar ao exato a vitória automática
#     mandaria a proposta da 48 a quem talvez tenha lido a 55; uma pergunta custa menos que o
#     arquivo errado. (A issue #396 escreve "exato > prefixo único > ambíguo" e, na linha seguinte,
#     pede "Bp" ambígua entre 48 e 55 — as duas coisas não cabem juntas com os nomes reais, e esta
#     é a leitura em que o exemplo da issue vale.)
#   - não é prefixo de nenhum -> NÃO COTOU, e a resposta lista quem cotou. Vale também para o nome
#     mais longo que o do portal ("Porto Seguro" contra "Porto"): a descrição do parâmetro manda o
#     modelo escrever o nome COMO SAIU NA LISTA DE PREÇOS, que é o mesmo mapa.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Escolha
  # `codigos`: os códigos escolhidos, na ordem em que foram falados, sem repetir (dois nomes que
  # casam com a mesma seguradora são UMA proposta). `ambiguas`: nome falado -> nomes candidatos.
  # `nao_cotaram`: os nomes falados que não casaram com ninguém.
  Resultado = Struct.new(:codigos, :ambiguas, :nao_cotaram, keyword_init: true) do
    def aceita?
      ambiguas.empty? && nao_cotaram.empty?
    end
  end

  module_function

  # `falados`: o que o modelo escreveu, já sem vazios. `mapa`: código -> nome, como a cotação gravou.
  def escolher(falados, mapa)
    nomes = mapa.to_h.to_h { |codigo, nome| [codigo.to_s, normalizar(nome)] }
    resultado = Resultado.new(codigos: [], ambiguas: {}, nao_cotaram: [])
    falados.each { |falado| casar(falado, nomes, mapa, resultado) }
    resultado
  end

  def casar(falado, nomes, mapa, resultado)
    candidatos = nomes.select { |_, nome| nome.start_with?(normalizar(falado)) }.keys
    case candidatos.size
    when 0 then resultado.nao_cotaram << falado
    when 1 then resultado.codigos |= candidatos
    else resultado.ambiguas[falado] = candidatos.map { |codigo| mapa[codigo].to_s }.sort_by { |nome| normalizar(nome) }
    end
  end

  # Minúsculas, sem acento, sem espaço duplo, sem espaço nas pontas — e só isso.
  def normalizar(texto)
    ActiveSupport::Inflector.transliterate(texto.to_s).downcase.squeeze(' ').strip
  end
end
