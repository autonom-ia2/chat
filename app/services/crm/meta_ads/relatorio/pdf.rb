# O PDF de Anúncios (#1960), A4 deitado, para mostrar ou mandar: o mesmo que a tela mostra no período.
# 1. Capa: a frase do período, quatro números (conversas, propostas, vendas e o investido ou o tempo de resposta), o
#    caminho até a venda desenhado e os anúncios que mais venderam, com a foto. Embaixo, o que cada palavra quer dizer.
# 2. Uma página por anúncio (até PAGINAS_DE_ANUNCIO, os que mais venderam): a foto, os números, as conversas por dia
#    e quem veio dele, cada pessoa com um selo da situação.
# 3. "Comece por aqui": quem chegou por anúncio e ainda espera resposta, a espera mais longa primeiro.
# O que não cabe (mais anúncios, mais pessoas) a página diz que está na planilha. Quem não pode exportar o CRM
# (Dados#com_pessoas?) recebe só os números: sem as pessoas por anúncio e sem a página de quem espera. Quem não vê os
# valores de venda (#2075) recebe as vendas sem o valor: o painel vem com o valor nil, e nil nunca vira "R$ 0".
class Crm::MetaAds::Relatorio::Pdf
  include Crm::MetaAds::Relatorio::Formato

  PAGINAS_DE_ANUNCIO = 8
  RANKING = 4
  PESSOAS_POR_ANUNCIO = 10
  ESPERANDO = 20
  LADO_DA_FOTO = 196
  # Coluna da direita da capa (ranking) começa aqui; o caminho até a venda ocupa a esquerda.
  DIREITA_DA_CAPA = 424
  TONS_DA_SITUACAO = { bought: :verde, talking: :azul, no_answer: :ambar, lost: :cinza }.freeze

  def initialize(dados, gerado_em: Time.current)
    @dados = dados
    @gerado_em = gerado_em.in_time_zone(dados.zona)
  end

  def nome
    "#{t('file_prefix')}-#{@gerado_em.strftime('%Y-%m-%d')}.pdf"
  end

  def gerar
    @pdf = Relatorios::Pdf.new(titulo: titulo, rodape: t('generated', date: momento(@gerado_em, @dados.zona)), pagina: t('page'))
    capa
    paginas_de_anuncio
    esperando if @dados.com_pessoas?
    @pdf.gerar
  end

  private

  def titulo
    "#{@dados.account.name} · #{t('title')}"
  end

  def totais
    @dados.totais
  end

  # O valor de venda escondido (nil, #2075) continua nil: nunca "R$ 0".
  def moeda(valor)
    dinheiro(valor, @dados.moeda) unless valor.nil?
  end

  def periodo
    t('period', name: nome_do_periodo(@dados.report), from: dia(@dados.report.first_day), to: dia(@dados.report.last_day))
  end

  def capa
    topo = @pdf.capa(conta: @dados.account.name, titulo: t('title'), periodo: periodo,
                     rotulo: t('hero_label', name: nome_do_periodo(@dados.report)), frase: frase)
    return @pdf.nota(t('empty'), topo: topo - 30, tamanho: 12) if totais[:conversations].to_i.zero?

    topo = @pdf.kpis(numeros, topo: topo + 34) - 26
    caminho(topo)
    melhores(topo)
    chamada_de_quem_espera
  end

  # No pé da capa: quantos esperam resposta, apontando a última página.
  def chamada_de_quem_espera
    total = @dados.sem_resposta(ESPERANDO)[:total]
    return if total.zero?

    texto = @dados.com_pessoas? ? t('waiting_callout', count: total) : t('waiting_callout_no_list', count: total)
    @pdf.chamada(texto, topo: Relatorios::Pdf::ALTURA_DA_CHAMADA + 4)
  end

  def frase
    conversas = t('count.conversations', count: totais[:conversations].to_i)
    vendas = t('count.sales', count: totais[:sales].to_i)
    return t('headline_whatsapp', conversations: conversas, sales: vendas) if @dados.sem_gasto?

    t('headline_spend', spend: moeda(totais[:spend]), conversations: conversas, sales: vendas)
  end

  def numeros
    [
      { rotulo: t('numbers.conversations'), valor: inteiro(totais[:conversations]), nota: t('numbers.conversations_note') },
      { rotulo: t('numbers.quotes'), valor: inteiro(totais[:quotes]), nota: t('numbers.open_quotes', count: totais[:open_quotes].to_i) },
      { rotulo: t('numbers.sales'), valor: inteiro(totais[:sales]), nota: moeda(totais[:sales_value]), destaque: true },
      @dados.sem_gasto? ? resposta : gasto
    ]
  end

  def gasto
    notas = [totais[:cost_per_sale] && t('numbers.cost_per_sale', value: moeda(totais[:cost_per_sale])),
             totais[:other_spend].to_f.positive? && t('numbers.other_spend', value: moeda(totais[:other_spend]))]
    { rotulo: t('numbers.spend'), valor: moeda(totais[:spend]), nota: notas.select(&:itself).join(' · ').presence }
  end

  def resposta
    tempo = @dados.tempo_de_resposta || {}
    sem_resposta = tempo[:unanswered].to_i
    nota = sem_resposta.positive? ? t('numbers.unanswered', count: sem_resposta) : t('numbers.response_note')
    { rotulo: t('numbers.response'), valor: tempo[:median_seconds] ? duracao(tempo[:median_seconds]) : '—', nota: nota }
  end

  # À esquerda: conversas → propostas → vendas em barras que encolhem; embaixo, o que cada palavra quer dizer.
  def caminho(topo)
    largura = DIREITA_DA_CAPA - 32
    topo = @pdf.titulo_de_secao(t('funnel_title'), topo: topo, largura_total: largura)
    topo = @pdf.funil(etapas, topo: topo, largura_total: largura)
    @pdf.nota(t('glossary'), topo: topo - 4, largura_total: largura, tamanho: 8.5)
  end

  def etapas
    conversas = [totais[:conversations].to_i, 1].max
    [
      { rotulo: t('numbers.conversations'), valor: inteiro(totais[:conversations]), parte: 1, nota: t('funnel_first') },
      etapa(t('numbers.quotes'), totais[:quotes], conversas),
      etapa(t('numbers.sales'), totais[:sales], conversas, moeda(totais[:sales_value]))
    ]
  end

  def etapa(rotulo, quantidade, conversas, extra = nil)
    parte = quantidade.to_f / conversas
    nota = [t('funnel_share', share: (parte * 100).round), extra].compact.join(' · ')
    { rotulo: rotulo, valor: inteiro(quantidade), parte: parte, nota: nota }
  end

  # À direita: os anúncios que mais venderam, com a foto.
  def melhores(topo)
    largura = @pdf.largura - DIREITA_DA_CAPA
    topo = @pdf.titulo_de_secao(t('ranking_title'), topo: topo, esquerda: DIREITA_DA_CAPA, largura_total: largura)
    topo = @pdf.ranking(@dados.anuncios.first(RANKING).map { |anuncio| item_do_ranking(anuncio) },
                        topo: topo, esquerda: DIREITA_DA_CAPA, largura_total: largura)
    resto = @dados.anuncios.size - RANKING
    @pdf.nota(t('ranking_more', count: resto), topo: topo + 2, esquerda: DIREITA_DA_CAPA, largura_total: largura) if resto.positive?
  end

  def item_do_ranking(anuncio)
    detalhe = t('ranking_detail', conversations: t('count.conversations', count: anuncio[:conversations].to_i),
                                  sales: t('count.sales', count: anuncio[:sales].to_i))
    { foto: @dados.foto(anuncio[:ad_id]), nome: nome_do_anuncio(anuncio), detalhe: detalhe, valor: moeda(anuncio[:sales_value]) }
  end

  def paginas_de_anuncio
    anuncios = @dados.anuncios.select { |anuncio| anuncio[:conversations].to_i.positive? }.first(PAGINAS_DE_ANUNCIO)
    anuncios.each_with_index do |anuncio, index|
      @pdf.nova_pagina
      pagina_do_anuncio(anuncio, index + 1, anuncios.size)
    end
  end

  def pagina_do_anuncio(anuncio, posicao, total)
    topo = @pdf.cabecalho(titulo: titulo, periodo: periodo)
    @pdf.foto({ foto: @dados.foto(anuncio[:ad_id]), nome: nome_do_anuncio(anuncio) }, esquerda: 0, topo: topo, lado: LADO_DA_FOTO)
    fim = lado_da_foto(anuncio, t('ad_counter', index: posicao, total: total), topo)
    pessoas_do_anuncio(anuncio, [fim, topo - LADO_DA_FOTO].min - 24) if @dados.com_pessoas?
  end

  # Ao lado da foto: qual anúncio é, o nome, os números e as conversas por dia. Devolve o topo abaixo do gráfico.
  def lado_da_foto(anuncio, contador, topo)
    x = LADO_DA_FOTO + 28
    largura = @pdf.largura - x
    doc = @pdf.doc
    doc.fill_color @pdf.cor(:suave)
    doc.text_box contador, at: [x, topo], width: largura, size: 9.5, style: :medium
    doc.fill_color @pdf.cor(:tinta)
    doc.text_box nome_do_anuncio(anuncio), at: [x, topo - 15], width: largura, height: 28, size: 21, style: :bold, overflow: :shrink_to_fit
    fim = @pdf.kpis(numeros_do_anuncio(anuncio), topo: topo - 52, esquerda: x, largura_total: largura)
    fim = @pdf.titulo_de_secao(t('chart'), topo: fim - 14, esquerda: x, largura_total: largura)
    @pdf.grafico(dias_do_grafico(anuncio), topo: fim, esquerda: x, largura_total: largura, altura_do_grafico: 44)
  end

  def dias_do_grafico(anuncio)
    @dados.dias.map { |data| I18n.l(data, format: '%d/%m') }.zip(@dados.por_dia(anuncio[:ad_id]))
  end

  def numeros_do_anuncio(anuncio)
    [
      { rotulo: t('numbers.conversations'), valor: inteiro(anuncio[:conversations]) },
      { rotulo: t('numbers.quotes'), valor: inteiro(anuncio[:quotes]), nota: t('numbers.open_quotes', count: abertas(anuncio)) },
      { rotulo: t('numbers.sales'), valor: inteiro(anuncio[:sales]), nota: moeda(anuncio[:sales_value]), destaque: true }
    ]
  end

  def pessoas_do_anuncio(anuncio, topo)
    lista = @dados.pessoas(anuncio[:ad_id], PESSOAS_POR_ANUNCIO)
    return if lista[:items].empty?

    topo = @pdf.titulo_de_secao(t('people'), topo: topo)
    topo = @pdf.pessoas(lista[:items].map { |item| pessoa_do_anuncio(item) }, topo: topo)
    resto = lista[:total] - lista[:items].size
    @pdf.nota(t('people_more', count: resto), topo: topo - 6) if resto.positive?
  end

  def pessoa_do_anuncio(item)
    chave = situacao(item)
    detalhe = [(dia(item[:touched_at].in_time_zone(@dados.zona)) if item[:touched_at]), item[:stage_name]].compact_blank.join(' · ')
    { nome: item[:title].presence || t('no_name'), detalhe: detalhe, selo: texto_da_situacao(item, chave), tom: TONS_DA_SITUACAO[chave] }
  end

  def texto_da_situacao(item, chave)
    texto = t("situation.#{chave}")
    chave == :bought && item[:value].to_f.positive? ? "#{texto} #{moeda(item[:value])}" : texto
  end

  def esperando
    lista = @dados.sem_resposta(ESPERANDO)
    return if lista[:items].empty?

    @pdf.nova_pagina
    topo = @pdf.cabecalho(titulo: titulo, periodo: periodo)
    topo = @pdf.titulo_de_secao(t('waiting_title', count: lista[:total]), topo: topo, nota: t('waiting_hint'))
    topo = @pdf.pessoas(lista[:items].map { |item| quem_espera(item) }, topo: topo - 6)
    resto = lista[:total] - lista[:items].size
    @pdf.nota(t('waiting_more', count: resto), topo: topo - 6) if resto.positive?
  end

  def quem_espera(item)
    chegou = item[:touched_at]
    detalhe = [item[:ad_name].presence || t('ad_no_name'), (momento(chegou, @dados.zona) if chegou)].compact.join(' · ')
    selo = chegou ? t('waiting_since', time: duracao(Time.current - chegou)) : t('situation.no_answer')
    { nome: item[:title].presence || t('no_name'), detalhe: detalhe, selo: selo, tom: :ambar }
  end
end
