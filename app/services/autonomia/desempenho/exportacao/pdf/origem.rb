# Página 05 do PDF (#2226): de onde vêm as procuras.
# (a) Sem anúncio rastreado: como chegaram (ranking, cada linha com quanto fechou) e, ao lado, a frase calma e as
#     ressalvas da conferência (ex.: um grupo que é piso). A taxa por grupo não se repete num segundo cartão.
# (b) Com anúncios: os dois cartões com a MESMA métrica (veio de anúncio × chegou sem anúncio), o ranking por anúncio
#     e o ranking de quem chegou sem anúncio. Em ambos, a nota da origem como ressalva.
module Autonomia::Desempenho::Exportacao::Pdf::Origem
  ALTURA_DO_LADO = 74
  PARTE_LARGA = 0.58

  def pagina_origem(_pagina)
    cima = abrir_pagina(t('origem.titulo'), t('origem.subtitulo'))
    origem = @painel['origem'].to_h
    cima = origem['anuncios_ligados'] ? origem_com_anuncio(origem, cima) : origem_sem_anuncio(origem, cima)
    return if origem['anuncios_ligados'].blank?

    cima = ressalvas_da_conferencia(%w[origem], 0, cima - 12, largura)
    notas = [origem['nota'].presence, t('origem.direct')].compact
    ressalva(notas.join(' '), 0, cima, largura)
  end

  private

  def coluna_larga
    (largura - 20) * PARTE_LARGA
  end

  def coluna_estreita
    largura - coluna_larga - 20
  end

  def linha_de_origem(grupo)
    { nome: grupo['nome'], valor: grupo['procuras'], pct: grupo['pct'],
      extra: frase_de_fechou('origem.fecham', grupo['fecharam'], grupo['compra'], grupo['taxa_pct']) }
  end

  def origem_sem_anuncio(origem, cima)
    grupos = Array(origem['grupos'])
    topo_do_bloco = titulo_do_bloco(t('origem.como_chegaram'), 0, cima, coluna_larga)
    fim_a = ranking(grupos.map { |grupo| linha_de_origem(grupo) }, 0, topo_do_bloco, coluna_larga, serie: 'volume', limite: 10)
    [fim_a, lado_calmo_da_origem(origem, coluna_larga + 20, cima)].min - 14
  end

  # A frase de quem não tem anúncio, as ressalvas da conferência (ex.: grupo que é piso) e a nota da origem.
  def lado_calmo_da_origem(origem, esq, cima)
    escrever(t('origem.sem_anuncio_frase'), esq, cima, coluna_estreita, tamanho: 9, tinta: :apoio, altura: 26)
    cima = ressalvas_da_conferencia(%w[origem], esq, cima - 30, coluna_estreita)
    origem['nota'].present? ? ressalva(origem['nota'], esq, cima, coluna_estreita, tamanho: 7.5) : cima
  end

  def origem_com_anuncio(origem, cima)
    cima = lados_da_origem(origem['comparacao'].to_h, cima) - 14
    fim_a = ranking_por_anuncio(origem, 0, cima)
    sem_anuncio = Array(origem['grupos']).select { |grupo| grupo['tipo'] == 'sem_anuncio' }.map { |grupo| linha_de_origem(grupo) }
    topo_b = titulo_do_bloco(t('origem.sem_anuncio_como'), coluna_larga + 20, cima, coluna_estreita)
    [fim_a, ranking(sem_anuncio, coluna_larga + 20, topo_b, coluna_estreita, serie: 'volume', limite: 6)].min
  end

  def lados_da_origem(comparacao, cima)
    metade = (largura - 16) / 2.0
    anuncio = comparacao['anuncio'].to_h
    sem = comparacao['sem_anuncio'].to_h
    vezes = razao_exata(anuncio, sem)
    lado_da_origem({ titulo: t('origem.veio_de_anuncio'), dados: anuncio, serie: 'resultado', vezes: vezes }, [0, cima, metade])
    lado_da_origem({ titulo: t('origem.chegou_sem_anuncio'), dados: sem, serie: 'volume', vezes: vezes && (1 / vezes) },
                   [metade + 16, cima, metade])
    cima - ALTURA_DO_LADO
  end

  # Quantas vezes a taxa de um lado é a do outro, pela conta exata (fecharam / pedidos de compra), nunca pelos %
  # arredondados. Lado sem base ou com poucos casos: nil.
  def razao_exata(lado, outro)
    return nil if [lado, outro].any? { |item| poucos_casos?(item['compra']) }

    taxa_outro = outro['fecharam'].to_f / outro['compra']
    taxa_outro.positive? ? (lado['fecharam'].to_f / lado['compra']) / taxa_outro : nil
  end

  # lado = { titulo:, dados:, serie:, vezes: }; caixa = [esq, cima, largura].
  def lado_da_origem(lado, caixa)
    esq, cima, largura_total = caixa
    cartao(esq, cima, largura_total, ALTURA_DO_LADO)
    faixa(esq + 6, cima, largura_total - 12, 3, serie(lado[:serie]))
    escrever_pilha(textos_do_lado(lado), esq + 12, cima, largura_total - 24)
  end

  def textos_do_lado(lado)
    dados = lado[:dados]
    [[lado[:titulo], 10, { tamanho: 9, estilo: :semibold, tinta: serie(lado[:serie], :texto) }],
     [t('origem.lado_procuras', n: numero(dados['procuras']), pct: pct(parte(dados['procuras'], meta.dig('base', 'procuras')))), 24, {}],
     [t('origem.lado_compra', compra: numero(dados['compra']), nome: nomes['compra'], fecharam: numero(dados['fecharam'])), 37,
      { tamanho: 8, tinta: :apoio }],
     [taxa_do_lado(lado), 50, { tamanho: 13, estilo: :bold }]]
  end

  def taxa_do_lado(lado)
    taxa = t('origem.lado_taxa', pct: pct(lado[:dados]['taxa_pct']))
    lado[:vezes].to_f > 1 ? "#{taxa}  ▲ #{t('origem.vezes', n: decimal(lado[:vezes]))}" : taxa
  end

  def ranking_por_anuncio(origem, esq, cima)
    cima = titulo_do_bloco(t('origem.por_anuncio'), esq, cima, coluna_larga)
    itens = Array(origem['anuncios']).map { |anuncio| { nome: anuncio['nome'], valor: anuncio['procuras'], extra: extra_do_anuncio(anuncio) } }
    cima = ranking(itens, esq, cima, coluna_larga, serie: 'resultado', limite: 6)
    return cima if origem['sem_saber_qual'].to_i.zero?

    escrever(t('origem.sem_saber_qual', n: numero(origem['sem_saber_qual'])), esq, cima - 4, coluna_larga, tamanho: 7.5, tinta: :apoio)
    cima - 16
  end

  def extra_do_anuncio(anuncio)
    custo = anuncio['custo_por_fechou'] && t('origem.custo_por_fechou', valor: dinheiro(anuncio['custo_por_fechou'], moeda_do_painel))
    [anuncio['campanha'].presence, t('origem.fecharam', n: numero(anuncio['fecharam'])), pct(anuncio['taxa_pct']), custo].compact.join(' · ')
  end

  def moeda_do_painel
    @painel.dig('ticket', 'moeda') || 'BRL'
  end
end
