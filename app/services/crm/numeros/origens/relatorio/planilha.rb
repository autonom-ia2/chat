# A planilha de Números › "De onde vieram os clientes" (#2001, F6), para trabalhar os números: os mesmos da tela no mês
# e no funil escolhidos (Relatorios::Planilha, a base da planilha de Anúncios).
# - Resumo: clientes novos, vendas, valor e, em "Todos os funis" e para quem vê os anúncios, o gasto;
# - Origens: uma por linha, com clientes novos, vendas e valor;
# - Anúncios: um por linha (com o gasto e o gasto por venda quando o gasto aparece);
# - Clientes: quem entrou ou fechou no mês, só para quem pode exportar o CRM (Dados#com_pessoas?).
# Sem os valores de venda (#2075), as colunas e linhas de valor saem: nada de coluna vazia nem de "R$ 0".
class Crm::Numeros::Origens::Relatorio::Planilha
  include Crm::Numeros::Origens::Relatorio::Formato

  def initialize(dados)
    @dados = dados
  end

  def nome
    nome_do_arquivo('xlsx')
  end

  def gerar
    montar.gerar
  end

  def montar
    Relatorios::Planilha.new.tap do |planilha|
      planilha.resumo(t('sheets.summary'), titulo: "#{@dados.account.name} · #{t('title')}", contexto: contexto, itens: resumo)
      aba(planilha, 'origins', colunas: colunas_de_origem, linhas: linhas_de_origem)
      aba(planilha, 'ads', colunas: colunas_de_anuncio, linhas: linhas_de_anuncio) if @dados.anuncios.any?
      aba(planilha, 'people', colunas: colunas_de_cliente, linhas: linhas_de_cliente, contexto: contexto_dos_clientes) if @dados.com_pessoas?
    end
  end

  private

  def aba(planilha, chave, colunas:, linhas:, contexto: self.contexto)
    planilha.aba(t("sheets.#{chave}"), titulo: t("sheets.#{chave}"), contexto: contexto, colunas: colunas, linhas: linhas)
  end

  def contexto
    t('sheet_context', filter: filtro, date: momento(gerado_em))
  end

  def contexto_dos_clientes
    lista = @dados.clientes
    return contexto if lista[:total] <= lista[:items].size

    "#{contexto} · #{t('sheet_truncated', shown: lista[:items].size, total: lista[:total])}"
  end

  def resumo
    itens = [[t('summary.clients'), @dados.origens.sum { |origem| origem[:clientes] }, :inteiro],
             [t('summary.sales'), @dados.origens.sum { |origem| origem[:vendas] }, :inteiro]]
    itens << [t('summary.sales_value'), @dados.origens.sum { |origem| origem[:valor].to_f }, :dinheiro] if @dados.valores?
    @dados.gasto ? itens + resumo_do_gasto : itens
  end

  def resumo_do_gasto
    gasto = @dados.gasto
    [
      [t('summary.spend'), gasto[:total], :dinheiro],
      ([t('summary.per_client'), gasto[:porCliente], :dinheiro] if gasto[:porCliente]),
      ([t('summary.per_sale'), gasto[:porVenda], :dinheiro] if gasto[:porVenda]),
      ([t('summary.return'), gasto[:retorno], :dinheiro] if gasto[:retorno]),
      [t('summary.touches'), gasto[:toques], :inteiro]
    ].compact
  end

  def colunas_de_origem
    [
      { titulo: t('columns.origin'), tipo: :texto, largura: 36 }, { titulo: t('columns.clients'), tipo: :inteiro, largura: 16 },
      { titulo: t('columns.sales'), tipo: :inteiro, largura: 10 },
      ({ titulo: t('columns.sales_value'), tipo: :dinheiro, largura: 16 } if @dados.valores?)
    ].compact
  end

  def linhas_de_origem
    @dados.origens.map do |origem|
      [nome_da_origem(origem[:tipo]), origem[:clientes], origem[:vendas], *([origem[:valor].to_f] if @dados.valores?)]
    end
  end

  def colunas_de_anuncio
    base = [{ titulo: t('columns.ad'), tipo: :texto, largura: 44 }, { titulo: t('columns.clients'), tipo: :inteiro, largura: 16 },
            { titulo: t('columns.sales'), tipo: :inteiro, largura: 10 }]
    base << { titulo: t('columns.sales_value'), tipo: :dinheiro, largura: 16 } if @dados.valores?
    return base unless @dados.gasto

    base + [{ titulo: t('columns.spend'), tipo: :dinheiro, largura: 14 }, { titulo: t('columns.per_sale'), tipo: :dinheiro, largura: 16 }]
  end

  def linhas_de_anuncio
    @dados.anuncios.map do |anuncio|
      linha = [nome_do_anuncio(anuncio), anuncio[:clientes], anuncio[:vendas]]
      linha << anuncio[:valor].to_f if @dados.valores?
      @dados.gasto ? linha + [anuncio[:gasto]&.to_f, anuncio[:porVenda]&.to_f] : linha
    end
  end

  def colunas_de_cliente
    [
      { titulo: t('columns.entered'), tipo: :data, largura: 17 }, { titulo: t('columns.contact'), tipo: :texto, largura: 28 },
      { titulo: t('columns.card'), tipo: :texto, largura: 28 }, { titulo: t('columns.pipeline'), tipo: :texto, largura: 18 },
      { titulo: t('columns.stage'), tipo: :texto, largura: 18 }, { titulo: t('columns.origin'), tipo: :texto, largura: 30 },
      { titulo: t('columns.ad'), tipo: :texto, largura: 30 }, { titulo: t('columns.situation'), tipo: :texto, largura: 14 },
      ({ titulo: t('columns.value'), tipo: :dinheiro, largura: 14 } if @dados.valores?)
    ].compact
  end

  def linhas_de_cliente
    @dados.clientes[:items].map do |item|
      [item[:entrou_em].in_time_zone(@dados.zona), item[:contato].to_s, item[:card].to_s, item[:funil].to_s, item[:etapa].to_s,
       nome_da_origem(item[:origem]), item[:anuncio].to_s, t("situation.#{item[:situacao]}"), *([item[:valor]] if @dados.valores?)]
    end
  end
end
