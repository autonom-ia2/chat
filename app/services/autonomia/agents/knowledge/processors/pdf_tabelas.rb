# #1431 (F1, PR 1b) — a tabela do PDF lida pela posição das células (incluído em Processors::Pdf, junto do PdfBlocos).
# Cada fileira vira um item com o cabeçalho da coluna de cada valor ("PLANO ANUAL Dias: 106 a 120 | % do Prêmio: 50%"):
# lida como texto corrido, a fileira de cinco planos lado a lado não dizia de que plano era cada número, e a linha certa
# da tabela de invalidez sumia diluída na tabela inteira. Só geometria (posição, letra, fonte); nada lê o texto.
# - célula: os trechos da linha separados por mais de GAP_DE_CELULA letras. O espaço entre palavras do texto justificado
#   é menor, e o parágrafo não vira tabela. Linha de duas células cuja segunda vai até a margem é item marcado (a cláusula
#   "5.1.5.  Restabelecido o pagamento…", o "•" do texto corrido), não fileira;
# - tabela: MIN_LINHAS_DA_TABELA ou mais linhas de duas células ou mais (só duas, com a primeira linha em destaque), com
#   até MAX_LINHAS_SOLTAS linhas de uma célula seguidas entre elas (a célula que quebra em duas linhas, o rótulo de um
#   grupo de fileiras), sem distância de mais de LONGE espaços normais entre duas linhas (o rodapé no pé da folha não
#   entra na tabela de cima);
# - fileira: as linhas mais próximas que MESMA_FILEIRA do espaço normal entre linhas são uma fileira; nela, as células que
#   se sobrepõem na horizontal são uma célula só (o texto que quebrou dentro da célula);
# - cabeçalho: as linhas curtas logo acima da tabela, sem espaço de parágrafo, e as primeiras fileiras fora da fonte do
#   corpo (o negrito do cabeçalho). Sem essa diferença de fonte, nenhuma fileira: tomar a primeira por cabeçalho dava
#   rótulo errado ("70: 50") na tabela que continua sem cabeçalho e na lista com marcador ("•");
# - coluna de cada pedaço do cabeçalho: a célula com o centro mais perto na fileira de mais células (a de referência), e
#   cada célula de cada fileira leva o título da coluna de referência mais perto dela; a coluna vazia numa fileira não
#   empresta o título à vizinha. O pedaço que cobre LARGA células ou
#   mais (palavras de colunas diferentes que o leitor juntou num trecho só) é dividido por palavra, cada uma na posição
#   proporcional dentro do trecho.
# Limites conhecidos: a tabela que continua na página seguinte não repete o cabeçalho lá; a célula que quebra em linhas
# no espaço normal vira duas fileiras.
module Autonomia::Agents::Knowledge::Processors::PdfTabelas
  GAP_DE_CELULA = 1.5
  MIN_LINHAS_DA_TABELA = 3
  MAX_LINHAS_SOLTAS = 3
  MESMA_FILEIRA = 0.75
  LARGA = 3
  LONGE = 4
  LEGENDA = 0.5
  ENTRE_CELULAS = ' | '.freeze

  private

  # Os pedaços da página, na ordem: { linhas: } do texto corrido e { tabela: true, cabecalho:, linhas: } de cada tabela.
  def pedacos_da_pagina(pagina)
    linhas = pagina[:linhas]
    pedacos = []
    inicio = 0
    faixas_de_tabela(pagina).each do |acima, primeira, ultima|
      pedacos << { linhas: linhas[inicio...acima] } if acima > inicio
      pedacos << { tabela: true, cabecalho: linhas[acima...primeira], linhas: linhas[primeira..ultima] }
      inicio = ultima + 1
    end
    inicio < linhas.size ? pedacos << { linhas: linhas[inicio..] } : pedacos
  end

  # [[acima, primeira, ultima]]: os índices do cabeçalho de cima, da primeira e da última linha de cada tabela.
  def faixas_de_tabela(pagina)
    linhas = pagina[:linhas]
    com_celulas = linhas.each_index.select { |indice| linha_de_tabela?(linhas[indice], pagina) }
    grupos = com_celulas.slice_when do |anterior, seguinte|
      seguinte - anterior > MAX_LINHAS_SOLTAS + 1 || longe?(linhas, anterior, seguinte, pagina)
    end
    grupos.select { |grupo| grupo.size >= MIN_LINHAS_DA_TABELA }
          .map { |grupo| [acima_da_tabela(linhas, grupo.first, pagina), grupo.first, grupo.last] }
          .select { |faixa| tabela?(linhas, faixa, pagina) }
  end

  # Só duas células por linha é tabela com cabeçalho: linhas curtas logo acima, ou a primeira linha fora da fonte do corpo
  # (o negrito). Sem ele, é o marcador da lista ou o número da cláusula curta e o texto (na letra 9 a folga do marcador
  # passa de GAP_DE_CELULA); e a tabela de duas colunas sem cabeçalho não ganharia título nenhum lida como tabela.
  def tabela?(linhas, (acima, primeira, ultima), pagina)
    acima < primeira || linhas[primeira][:fonte].exclude?(pagina[:fonte_do_corpo]) ||
      linhas[primeira..ultima].any? { |linha| celulas(linha).size > 2 }
  end

  def linha_de_tabela?(linha, pagina)
    quantas = celulas(linha).size
    quantas > 2 || (quantas == 2 && antes_da_margem?(linha, pagina))
  end

  # Alguma das linhas entre as duas (índices) está a mais de LONGE espaços normais da seguinte.
  def longe?(linhas, anterior, seguinte, pagina)
    (anterior...seguinte).any? { |indice| linhas[indice][:y] - linhas[indice + 1][:y] > pagina[:normal] * LONGE }
  end

  # Sobe pelas linhas de uma célula coladas à tabela (sem espaço de parágrafo): o cabeçalho de uma célula só ("% SOBRE",
  # "Invalidez"). Para na linha cheia de parágrafo (da esquerda do corpo até a margem), no título (letra maior, ou fora da
  # fonte do corpo: "Tabela 2 – Prazos" em negrito) e na legenda (linha mais larga que LEGENDA da largura do corpo): a
  # legenda repetida em cada fileira diluía a fileira, e o título da tabela já vai no caminho do trecho. Também não sobe
  # pela última linha de um parágrafo (a linha de cima é cheia e está no espaço normal): ela é o fim do texto de introdução.
  def acima_da_tabela(linhas, primeira, pagina)
    acima = primeira
    acima -= 1 while acima.positive? && cabecalho_acima?(linhas[acima - 1], linhas[acima], pagina) &&
                     !fim_de_paragrafo?(linhas, acima - 1, pagina)
    acima
  end

  def fim_de_paragrafo?(linhas, indice, pagina)
    de_cima = linhas[indice - 1]
    indice.positive? && cheia?(de_cima, pagina) && !separado?(de_cima, linhas[indice], pagina[:normal])
  end

  def cabecalho_acima?(linha, de_baixo, pagina)
    celulas(linha).size == 1 && !cheia?(linha, pagina) && !letra_maior?(linha, pagina) && !legenda?(linha, pagina) &&
      linha[:fonte].include?(pagina[:fonte_do_corpo]) && !separado?(linha, de_baixo, pagina[:normal])
  end

  def legenda?(linha, pagina)
    largura = linha[:trechos].last[:fim] - linha[:trechos].first[:x]
    largura > (pagina[:corpo].pluck(:direita).max - esquerda_do_corpo(pagina)) * LEGENDA
  end

  def cheia?(linha, pagina)
    !antes_da_margem?(linha, pagina) && linha[:trechos].first[:x] <= esquerda_do_corpo(pagina) + linha[:letra]
  end

  def esquerda_do_corpo(pagina)
    pagina[:corpo].filter_map { |de_corpo| de_corpo[:trechos].first&.dig(:x) }.min
  end

  # { tipo: :tabela, texto:, itens:, pagina: }: cada item é uma fileira com o cabeçalho de cada coluna, e o texto (para o
  # trecho da seção) são os itens, um por linha.
  def bloco_da_tabela(pedaco, pagina, numero)
    fileiras = fileiras_da_tabela(pedaco[:linhas], pagina)
    de_cabecalho = fileiras_de_cabecalho(fileiras, pagina)
    pedacos = (pedaco[:cabecalho] + fileiras.first(de_cabecalho).flatten).flat_map { |linha| celulas(linha) }
    dados = fileiras.drop(de_cabecalho).map { |fileira| celulas_da_fileira(fileira) }
    referencia = dados.max_by(&:size) || []
    titulos = titulos_das_colunas(pedacos, referencia)
    itens = dados.map { |celulas| item_da_fileira(celulas, referencia, titulos) }
    { tipo: :tabela, texto: itens.join("\n"), itens: itens, pagina: numero }
  end

  def fileiras_da_tabela(linhas, pagina)
    linhas.slice_when { |de_cima, de_baixo| de_cima[:y] - de_baixo[:y] > pagina[:normal] * MESMA_FILEIRA }.to_a
  end

  # As primeiras fileiras fora da fonte do corpo; com a tabela toda fora dela, nenhuma.
  def fileiras_de_cabecalho(fileiras, pagina)
    destacadas = fileiras.take_while do |fileira|
      fileira.all? { |linha| linha[:fonte].exclude?(pagina[:fonte_do_corpo]) }
    end.size
    destacadas < fileiras.size ? destacadas : 0
  end

  # As células da linha: trechos com folga até GAP_DE_CELULA letras ficam na mesma célula.
  def celulas(linha)
    linha[:trechos].slice_when { |anterior, trecho| trecho[:x] - anterior[:fim] > linha[:letra] * GAP_DE_CELULA }.map do |grupo|
      { x: grupo.first[:x], fim: grupo.last[:fim], texto: grupo.pluck(:texto).join(' ') }
    end
  end

  # As células da fileira, da esquerda para a direita; as que se sobrepõem na horizontal (de linhas diferentes) são uma.
  def celulas_da_fileira(fileira)
    colunas = fileira.flat_map { |linha| celulas(linha) }.each_with_object([]) do |celula, juntas|
      junto = juntas.index { |coluna| sobrepoe?(coluna, celula) }
      next juntas << celula if junto.nil?

      juntas[junto] = juntar_celulas(juntas[junto], celula)
    end
    colunas.sort_by { |celula| celula[:x] }
  end

  def juntar_celulas(coluna, celula)
    { x: [coluna[:x], celula[:x]].min, fim: [coluna[:fim], celula[:fim]].max, texto: "#{coluna[:texto]} #{celula[:texto]}" }
  end

  # { índice da coluna de referência => título }.
  def titulos_das_colunas(pedacos, referencia)
    return {} if referencia.empty?

    por_coluna = pedacos.flat_map { |pedaco| divididos(pedaco, referencia) }.group_by { |pedaco| mais_perto(pedaco, referencia) }
    por_coluna.transform_values { |doscabecalho| doscabecalho.pluck(:texto).join(' ') }
  end

  def item_da_fileira(celulas, referencia, titulos)
    rotuladas = celulas.map do |celula|
      titulo = titulos[mais_perto(celula, referencia)].to_s
      titulo.empty? ? celula[:texto] : "#{titulo}: #{celula[:texto]}"
    end
    rotuladas.join(ENTRE_CELULAS)
  end

  # O pedaço do cabeçalho sobre LARGA células ou mais vira uma palavra por pedaço, na posição proporcional ao lugar dela
  # no texto do trecho.
  def divididos(pedaco, celulas)
    return [pedaco] if celulas.count { |celula| sobrepoe?(celula, pedaco) } < LARGA

    texto = pedaco[:texto]
    largura = (pedaco[:fim] - pedaco[:x]) / texto.length.to_f
    depois = 0
    texto.split.map do |palavra|
      comeco = texto.index(palavra, depois)
      depois = comeco + palavra.length
      { x: pedaco[:x] + (comeco * largura), fim: pedaco[:x] + (depois * largura), texto: palavra }
    end
  end

  def mais_perto(pedaco, celulas)
    celulas.each_index.min_by { |indice| (centro(celulas[indice]) - centro(pedaco)).abs }
  end

  def centro(celula)
    (celula[:x] + celula[:fim]) / 2.0
  end

  def sobrepoe?(uma, outra)
    uma[:x] < outra[:fim] && outra[:x] < uma[:fim]
  end
end
