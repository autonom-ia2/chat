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
#   - o falado é IGUAL a um nome cotado -> é esse, e a busca acaba aí ("bp" -> "Bp", código 48,
#     mesmo com "Bp Assinatura" cotada). O exato vence porque o cliente leu a lista e escreveu o
#     que leu: com 48 "Bp" e 55 "Bp Assinatura" cotadas (nomes reais do portal, medidos em
#     11/09/2026), sem esta regra a 48 era INSELECIONÁVEL — qualquer texto que a alcançasse
#     alcançava também a 55 (Codex, P2 da rodada de correção). A primeira versão desta ferramenta
#     tratava "Bp" como ambígua, pela leitura de que uma pergunta custa menos que o arquivo errado;
#     a revisão mostrou que o preço dessa leitura era não haver frase nenhuma que pedisse a 48;
#   - não é igual a nenhum, e é PREFIXO de exatamente um -> é esse ("suh" -> "Suhai"; "bp a" ->
#     "Bp Assinatura"). Prefixo, não pedaço: "assinatura" não casa "Bp Assinatura";
#   - não é igual a nenhum, e é prefixo de mais de um -> AMBÍGUO, e a resposta lista as candidatas
#     ("b" com Bp e Bp Assinatura cotadas);
#   - não é igual nem prefixo de nenhum -> NÃO COTOU, e a resposta lista quem cotou. Vale também
#     para o nome mais longo que o do portal ("Porto Seguro" contra "Porto"): a descrição do
#     parâmetro manda o modelo escrever o nome COMO SAIU NA LISTA DE PREÇOS, que é o mesmo mapa.
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
    candidatos = candidatos_de(normalizar(falado), nomes)
    case candidatos.size
    when 0 then resultado.nao_cotaram << falado
    when 1 then resultado.codigos |= candidatos
    else resultado.ambiguas[falado] = candidatos.map { |codigo| mapa[codigo].to_s }.sort_by { |nome| normalizar(nome) }
    end
  end

  # O EXATO VENCE; só sem exato é que o prefixo conta. -> códigos candidatos.
  def candidatos_de(falado, nomes)
    exatos = nomes.select { |_, nome| nome == falado }.keys
    return exatos if exatos.any?

    nomes.select { |_, nome| nome.start_with?(falado) }.keys
  end

  # Minúsculas, sem acento, sem espaço duplo, sem espaço nas pontas — e só isso.
  def normalizar(texto)
    ActiveSupport::Inflector.transliterate(texto.to_s).downcase.squeeze(' ').strip
  end
end
