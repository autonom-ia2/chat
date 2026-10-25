# A planilha de Anúncios (#1960), para trabalhar os números: as mesmas contas da tela no período, em quatro abas.
# - Resumo: os números do período;
# - Anúncios: um por linha, com conversas, propostas abertas, vendas e valor (e, com conexão, investido e custo);
# - Conversas: cada pessoa que chegou por anúncio (só as que a pessoa vê), com etapa, situação, valor e resposta;
#   só para quem pode exportar o CRM (Dados#com_pessoas?);
# - Por dia: conversas de cada dia, no total e por anúncio.
# Sem os valores de venda (Dados#valores?, #2075), o valor vendido sai do resumo e a coluna de valor sai das abas
# Anúncios e Conversas: nada de coluna vazia nem de "R$ 0".
class Crm::MetaAds::Relatorio::Planilha
  include Crm::MetaAds::Relatorio::Formato

  # Colunas de anúncio na aba Por dia; o resto entra só no total.
  ANUNCIOS_POR_DIA = 25

  def initialize(dados, gerado_em: Time.current)
    @dados = dados
    @gerado_em = gerado_em.in_time_zone(dados.zona)
  end

  def nome
    "#{t('file_prefix')}-#{@gerado_em.strftime('%Y-%m-%d')}.xlsx"
  end

  def gerar
    montar.gerar
  end

  def montar
    Relatorios::Planilha.new.tap do |planilha|
      planilha.resumo(t('sheets.summary'), titulo: "#{@dados.account.name} · #{t('title')}", contexto: contexto, itens: resumo)
      aba(planilha, 'ads', colunas: colunas_de_anuncio, linhas: linhas_de_anuncio)
      if @dados.com_pessoas?
        aba(planilha, 'conversations', colunas: colunas_de_conversa, linhas: linhas_de_conversa, contexto: contexto_das_conversas)
      end
      aba(planilha, 'daily', colunas: colunas_por_dia, linhas: linhas_por_dia)
    end
  end

  private

  def aba(planilha, chave, colunas:, linhas:, contexto: self.contexto)
    planilha.aba(t("sheets.#{chave}"), titulo: t("sheets.#{chave}"), contexto: contexto, colunas: colunas, linhas: linhas)
  end

  def totais
    @dados.totais
  end

  def contexto
    t('sheet_context', name: nome_do_periodo(@dados.report), from: dia(@dados.report.first_day), to: dia(@dados.report.last_day),
                       date: momento(@gerado_em, @dados.zona))
  end

  def contexto_das_conversas
    lista = @dados.conversas
    return contexto if lista[:total] <= lista[:items].size

    "#{contexto} · #{t('sheet_truncated', shown: lista[:items].size, total: lista[:total])}"
  end

  def resumo
    itens = %i[conversations quotes open_quotes sales].map { |chave| [t("summary.#{chave}"), totais[chave].to_i, :inteiro] }
    itens << [t('summary.sales_value'), totais[:sales_value].to_f, :dinheiro] if @dados.valores?
    itens += gasto unless @dados.sem_gasto?
    itens + resumo_da_resposta
  end

  def resumo_da_resposta
    tempo = @dados.tempo_de_resposta
    return [] if tempo.nil?

    mediana = tempo[:median_seconds] ? [[t('summary.response'), duracao(tempo[:median_seconds]), :texto]] : []
    mediana + [[t('summary.unanswered'), tempo[:unanswered].to_i, :inteiro]]
  end

  def gasto
    [[t('summary.spend'), totais[:spend].to_f, :dinheiro]] +
      (totais[:cost_per_sale] ? [[t('summary.cost_per_sale'), totais[:cost_per_sale].to_f, :dinheiro]] : []) +
      (totais[:other_spend].to_f.positive? ? [[t('summary.other_spend'), totais[:other_spend].to_f, :dinheiro]] : [])
  end

  def colunas_de_anuncio
    base = [
      { titulo: t('columns.ad'), tipo: :texto, largura: 44 }, { titulo: t('columns.conversations'), tipo: :inteiro, largura: 14 },
      { titulo: t('columns.open_quotes'), tipo: :inteiro, largura: 18 }, { titulo: t('columns.sales'), tipo: :inteiro, largura: 10 }
    ]
    base << { titulo: t('columns.sales_value'), tipo: :dinheiro, largura: 16 } if @dados.valores?
    return base if @dados.sem_gasto?

    base + [{ titulo: t('columns.spend'), tipo: :dinheiro, largura: 14 }, { titulo: t('columns.cost_per_sale'), tipo: :dinheiro, largura: 16 }]
  end

  def linhas_de_anuncio
    @dados.anuncios.map do |anuncio|
      linha = [nome_do_anuncio(anuncio), anuncio[:conversations].to_i, abertas(anuncio), anuncio[:sales].to_i]
      linha << anuncio[:sales_value].to_f if @dados.valores?
      @dados.sem_gasto? ? linha : linha + [anuncio[:spend].to_f, anuncio[:cost_per_sale]&.to_f]
    end
  end

  def colunas_de_conversa
    [
      { titulo: t('columns.date'), tipo: :data, largura: 17 }, { titulo: t('columns.person'), tipo: :texto, largura: 30 },
      { titulo: t('columns.ad'), tipo: :texto, largura: 36 }, { titulo: t('columns.stage'), tipo: :texto, largura: 20 },
      { titulo: t('columns.situation'), tipo: :texto, largura: 16 },
      ({ titulo: t('columns.value'), tipo: :dinheiro, largura: 14 } if @dados.valores?),
      { titulo: t('columns.response'), tipo: :texto, largura: 16 }
    ].compact
  end

  def linhas_de_conversa
    @dados.conversas[:items].map do |item|
      [item[:touched_at]&.in_time_zone(@dados.zona), item[:title].presence || t('no_name'), item[:ad_name].presence || t('ad_no_name'),
       item[:stage_name].to_s, t("situation.#{situacao(item)}"), *([item[:value]&.to_f] if @dados.valores?), resposta(item)]
    end
  end

  def resposta(item)
    item[:answered] && item[:response_seconds] ? duracao(item[:response_seconds]) : ''
  end

  def anuncios_por_dia
    @anuncios_por_dia ||= @dados.anuncios.select { |anuncio| anuncio[:conversations].to_i.positive? }.first(ANUNCIOS_POR_DIA)
  end

  def colunas_por_dia
    [{ titulo: t('columns.day'), tipo: :dia, largura: 13 }, { titulo: t('columns.conversations'), tipo: :inteiro, largura: 14 }] +
      anuncios_por_dia.map { |anuncio| { titulo: nome_do_anuncio(anuncio), tipo: :inteiro, largura: 22 } }
  end

  def linhas_por_dia
    contagens = anuncios_por_dia.map { |anuncio| @dados.por_dia(anuncio[:ad_id]) }
    totais_do_dia = @dados.report.cohort.touches.values.map { |_ad, at| at.in_time_zone(@dados.zona).to_date }.tally
    @dados.dias.each_with_index.map do |data, index|
      [data, totais_do_dia.fetch(data, 0)] + contagens.map { |contagem| contagem[index] }
    end
  end
end
