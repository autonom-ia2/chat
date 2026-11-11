# A DESCRIÇÃO COMPLETA de um código da NCM (#2858, achado do teste em produção de 11/11/2026). A tabela do Siscomex dá a
# cada nível só o texto relativo ao pai, com os traços do nível e os dois-pontos do grupo: "0901.2 | - Café torrado:" e,
# abaixo dele, "0901.21.00 | -- Não descafeinado". Sozinho, o código da nota dizia só "Não descafeinado".
#   - `limpa`: o texto sem os traços do começo e sem o ":" do fim ("Café torrado");
#   - `completa`: o código sobe pela hierarquia dos itens que vieram (o pai é o código cujos dígitos começam os dele):
#     posição (4 dígitos), subposição (5 e 6) e item (7), de cima para baixo, e o texto dele por último, com vírgula
#     ("Café, mesmo torrado ou descafeinado; …, café torrado, não descafeinado"). A posição entra sempre que veio: é ela
#     que diz o material ("de ferro fundido, ferro ou aço" no 73.18, "de cobre" no 74.15; revisão do #2917). O capítulo
#     (2) e a posição têm o texto inteiro.
# Trabalha sobre o `Nivel` (o texto de cada item já lido). Sem regex: `start_with?`, `delete_prefix` e `delete_suffix`.
module Autonomia::FerramentasProntas::Fontes::Ncm::Descricao
  SEPARADOR = ', '.freeze
  RETICENCIAS = ' … '.freeze
  # Menos que isso de um pai resumido não diz nada.
  MINIMO = 30

  module_function

  # "-- Não descafeinado" -> "Não descafeinado"; "- Café torrado:" -> "Café torrado".
  def limpa(texto)
    resto = texto.to_s.strip
    resto = resto.delete_prefix('-').lstrip while resto.start_with?('-')
    resto.delete_suffix(':').rstrip
  end

  # Os níveis da mesma resposta (e da chamada a mais) pelos dígitos, montado uma vez: o pai de cada nível se acha sem
  # varrer a lista.
  def indice(niveis)
    niveis.index_by(&:digitos)
  end

  # `indice`: o que `indice` monta. Os textos de cima perdem o ponto final; os de baixo começam com minúscula, menos a
  # sigla ("PVC"). Cabe no texto que vai ao modelo (`Resposta::MAX_TEXTO`), e o texto do próprio código vai sempre
  # inteiro, no fim: é ele que separa um código do irmão (revisão do #2917: o corte do fim deixava "brinquedos" com 20
  # códigos e 3 descrições). Quem encurta são os pais (`no_limite`). O texto próprio que sozinho passa do teto (o
  # 7616.10.00 tem 200 letras) não tira os pais: eles ficam com ao menos `MINIMO`, porque a posição diz o material
  # ("Outras obras de alumínio"), e o fim do texto próprio é que fica no corte do `Resposta`. O que cabe sozinho vai
  # sempre inteiro (o 3004.39.91, 139 letras).
  def completa(nivel, indice)
    propria = nivel.propria
    pais = acima(nivel, indice).map { |pai| pai.propria.delete_suffix('.') }.reject(&:empty?).uniq - [propria]
    junta(no_limite(pais, espaco_dos_pais(propria)) + [propria])
  end

  def espaco_dos_pais(propria)
    teto = Autonomia::FerramentasProntas::Resposta::MAX_TEXTO
    propria.length > teto ? MINIMO + SEPARADOR.length : teto - propria.length
  end

  def junta(partes)
    ([partes.first] + partes.drop(1).map { |parte| minuscula(parte) }).join(SEPARADOR)
  end

  # Os pais dentro de `espaco` (com o separador depois de cada um). Os de baixo inteiros, que dizem a diferença entre
  # irmãos; o de cima (o mais longo, a posição: 218 letras no 73.18) resumido no começo e no fim, onde fica o material.
  # Sem lugar nem para isso: todos juntos num resumo só; com menos de `MINIMO` letras, nenhum.
  def no_limite(pais, espaco)
    return pais if ocupa(pais) <= espaco

    de_baixo = pais.drop(1)
    resta = espaco - ocupa(de_baixo) - SEPARADOR.length
    return [resumo(pais.first, resta)] + de_baixo if resta >= MINIMO

    resta = espaco - SEPARADOR.length
    resta >= MINIMO ? [resumo(junta(pais), resta)] : []
  end

  def ocupa(partes)
    partes.sum { |parte| parte.length + SEPARADOR.length }
  end

  # O começo e o fim do texto, em palavras inteiras, com reticências no meio.
  def resumo(texto, espaco)
    return texto if texto.length <= espaco

    metade = (espaco - RETICENCIAS.length) / 2
    "#{comeco(texto, metade)}#{RETICENCIAS}#{fim(texto, metade)}"
  end

  def comeco(texto, tamanho)
    parte = texto.first(tamanho + 1)
    parte = parte.include?(' ') ? parte[0, parte.rindex(' ')] : parte.first(tamanho)
    parte.delete_suffix(',').delete_suffix(';')
  end

  def fim(texto, tamanho)
    parte = texto.last(tamanho + 1)
    parte.include?(' ') ? parte[(parte.index(' ') + 1)..] : parte.last(tamanho)
  end

  # Os pais que vieram, de cima para baixo: o código com os primeiros 4, 5, 6 e 7 dígitos deste.
  def acima(nivel, indice)
    (ncm::POSICAO...nivel.digitos.length).filter_map { |tamanho| indice[nivel.digitos.first(tamanho)] }
  end

  # Vieram os níveis de cima: a posição, que diz o que é a mercadoria ("Animais vivos da espécie bovina"), e tantos
  # quantos os traços do nível ("-- Parafusos autoperfurantes" fica abaixo da posição e de uma subposição). Na tabela
  # sem a posição de 4 dígitos (o 95.03 não existe na BrasilAPI), a subposição "9503.00" faz o papel dela (revisão do
  # #2917: "0102.29.19 Outros" sem o 01.02 contava como inteira).
  def inteira?(nivel, indice)
    pais = acima(nivel, indice)
    pais.size >= nivel.tracos && pais.any? { |pai| posicao?(pai) }
  end

  def posicao?(nivel)
    nivel.digitos.length == ncm::POSICAO || (nivel.digitos.length == ncm::SUBPOSICAO && nivel.digitos.end_with?('00'))
  end

  def minuscula(texto)
    segunda = texto[1].to_s
    segunda == segunda.downcase ? "#{texto[0].downcase}#{texto[1..]}" : texto
  end

  def ncm
    Autonomia::FerramentasProntas::Fontes::Ncm
  end
end
