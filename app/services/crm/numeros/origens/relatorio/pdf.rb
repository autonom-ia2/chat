# O PDF de Números › "De onde vieram os clientes" (#2001, F6), A4 deitado, para mostrar ou mandar: o mesmo que a tela
# mostra no mês e no funil escolhidos (Relatorios::Pdf, a base do relatório de Anúncios).
# 1. Capa: o filtro, a frase de onde veio a maior parte, os números (clientes novos, vendas e, em "Todos os funis" e
#    para quem vê os anúncios, o gasto e o gasto por cliente novo), de onde vieram e os anúncios que mais venderam.
# 2. Os clientes do mês, com a origem e a situação, só para quem pode exportar o CRM (Dados#com_pessoas?).
# Quem não vê os valores de venda (#2075) recebe as vendas sem o R$: o valor vem nil e nil nunca vira "R$ 0".
class Crm::Numeros::Origens::Relatorio::Pdf
  include Crm::Numeros::Origens::Relatorio::Formato

  RANKING = 4
  ORIGENS = 6
  PESSOAS = 26
  # Coluna da direita da capa (anúncios) começa aqui; as origens ocupam a esquerda.
  DIREITA_DA_CAPA = 424
  TONS = { sale: :verde, open: :azul, lost: :cinza, closed: :cinza }.freeze

  def initialize(dados)
    @dados = dados
  end

  def nome
    nome_do_arquivo('pdf')
  end

  def gerar
    @pdf = Relatorios::Pdf.new(titulo: titulo, rodape: t('generated', date: momento(gerado_em)), pagina: t('page'))
    capa
    clientes if @dados.com_pessoas?
    @pdf.gerar
  end

  private

  def titulo
    "#{@dados.account.name} · #{t('title')}"
  end

  def capa
    topo = @pdf.capa(conta: @dados.account.name, titulo: t('title'), periodo: filtro,
                     rotulo: t('hero_label', month: nome_do_mes), frase: frase)
    return @pdf.nota(t('headline_none'), topo: topo - 30, tamanho: 12) if @dados.vazio?

    topo = @pdf.kpis(numeros, topo: topo + 34) - 26
    de_onde(topo)
    melhores(topo) if @dados.anuncios.any?
    chamada
  end

  def total_de_clientes
    @dados.origens.sum { |origem| origem[:clientes] }
  end

  def frase
    primeira = @dados.origens.find { |origem| origem[:tipo] != Crm::Numeros::Origens::Classificador::OUTRAS }
    return t('headline_none') if primeira.nil?

    t('headline', count: primeira[:clientes], total: total_de_clientes, origin: nome_da_origem(primeira[:tipo]))
  end

  def numeros
    vendas = @dados.origens.sum { |origem| origem[:vendas] }
    valor = @dados.valores? ? @dados.origens.sum { |origem| origem[:valor].to_f } : nil
    base = [
      { rotulo: t('numbers.clients'), valor: inteiro(total_de_clientes), nota: t('numbers.clients_note') },
      { rotulo: t('numbers.sales'), valor: inteiro(vendas), nota: dinheiro(valor) || t('numbers.sales_note'), destaque: true }
    ]
    @dados.gasto ? base + numeros_do_gasto : base
  end

  def numeros_do_gasto
    gasto = @dados.gasto
    [
      { rotulo: t('numbers.spend'), valor: dinheiro(gasto[:total]),
        nota: (t('numbers.per_sale', value: dinheiro(gasto[:porVenda])) if gasto[:porVenda]) },
      ({ rotulo: t('numbers.per_client'), valor: dinheiro(gasto[:porCliente]) } if gasto[:porCliente])
    ].compact
  end

  # À esquerda (ou na largura toda, sem anúncio): cada origem com os clientes novos e as vendas.
  def de_onde(topo)
    largura = @dados.anuncios.any? ? DIREITA_DA_CAPA - 32 : @pdf.largura
    topo = @pdf.titulo_de_secao(t('origins_title'), topo: topo, largura_total: largura)
    @pdf.pessoas(@dados.origens.first(ORIGENS).map { |origem| item_da_origem(origem) }, topo: topo, largura_total: largura, colunas: 1)
  end

  def item_da_origem(origem)
    { nome: nome_da_origem(origem[:tipo]), detalhe: vendas_e_valor(origem), selo: t('count.clients', count: origem[:clientes]), tom: :azul }
  end

  def vendas_e_valor(linha)
    [t('count.sales', count: linha[:vendas]), (dinheiro(linha[:valor]) if linha[:vendas].positive?)].compact.join(' · ')
  end

  # À direita: os anúncios que mais venderam.
  def melhores(topo)
    largura = @pdf.largura - DIREITA_DA_CAPA
    topo = @pdf.titulo_de_secao(t('ads_title'), topo: topo, esquerda: DIREITA_DA_CAPA, largura_total: largura)
    itens = @dados.anuncios.first(RANKING).map { |anuncio| item_do_anuncio(anuncio) }
    topo = @pdf.ranking(itens, topo: topo, esquerda: DIREITA_DA_CAPA, largura_total: largura)
    resto = @dados.anuncios.size - RANKING
    @pdf.nota(t('ads_more', count: resto), topo: topo + 2, esquerda: DIREITA_DA_CAPA, largura_total: largura) if resto.positive?
  end

  def item_do_anuncio(anuncio)
    detalhe = [t('count.clients', count: anuncio[:clientes]), t('count.sales', count: anuncio[:vendas])].join(' · ')
    { foto: nil, nome: nome_do_anuncio(anuncio), detalhe: detalhe, valor: (dinheiro(anuncio[:valor]) if anuncio[:vendas].positive?) }
  end

  # No pé da capa: o retorno do gasto, ou, com um funil escolhido, onde está o gasto.
  def chamada
    texto = retorno || (t('spend_only_all') if @dados.payload[:gastoEmTodos])
    @pdf.chamada(texto, topo: Relatorios::Pdf::ALTURA_DA_CHAMADA + 4, tom: :verde) if texto
  end

  def retorno
    valor = @dados.gasto&.dig(:retorno)
    t('numbers.return', one: dinheiro(1), value: dinheiro(valor)) if valor
  end

  def clientes
    lista = @dados.clientes
    return if lista[:items].empty?

    @pdf.nova_pagina
    topo = @pdf.cabecalho(titulo: titulo, periodo: filtro)
    topo = @pdf.titulo_de_secao(t('people_title'), topo: topo)
    topo = @pdf.pessoas(lista[:items].first(PESSOAS).map { |item| pessoa(item) }, topo: topo)
    resto = lista[:total] - [lista[:items].size, PESSOAS].min
    @pdf.nota(t('people_more', count: resto), topo: topo - 6) if resto.positive?
  end

  def pessoa(item)
    detalhe = [I18n.l(item[:entrou_em].in_time_zone(@dados.zona).to_date, format: '%d/%m'), nome_da_origem(item[:origem]),
               item[:etapa]].compact_blank.join(' · ')
    selo = t("situation.#{item[:situacao]}")
    selo = "#{selo} #{dinheiro(item[:valor])}" if item[:situacao] == :sale && item[:valor].to_f.positive?
    { nome: item[:contato].presence || item[:card].presence || t('no_name'), detalhe: detalhe, selo: selo, tom: TONS[item[:situacao]] }
  end
end
