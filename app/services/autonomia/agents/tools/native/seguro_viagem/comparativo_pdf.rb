# O COMPARATIVO EM PDF do Seguro Viagem (#3211): uma folha A4 paisagem, um plano por coluna, para o cliente ler com
# calma o que a Lia disse na conversa. Sai da cotação guardada (`planos` no formato de `Planos.de`) e não lê banco nem
# chama a seguradora.
#
# O QUE NUNCA ENTRA (R2): comissão, markup, ranking, `id_produto`, o código interno do plano (`P1`) e dado pessoal.
# `Planos.de` já não traz comissão nem ranking; aqui só se lê a lista branca de chaves abaixo. Do cliente só as idades.
#
# As cores e a fonte são as dos outros PDFs do produto (`Exportacao::Pdf::COR`, `Relatorios::Pdf::FONTES`).
class Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  COR = Autonomia::Desempenho::Exportacao::Pdf::COR
  FONTES = Relatorios::Pdf::FONTES
  MARGEM = 32
  LARGURA_DO_ROTULO = 150
  SEM_VALOR = '—'.freeze
  TEXTOS = {
    titulo: 'Comparativo de seguro viagem', destinos: 'Destino', datas: 'Período', viajantes: 'Viajantes',
    plano: 'Plano', total: 'Preço total', por_pessoa: 'Preço por pessoa', parcelas: 'Parcelamento',
    cotado_em: 'Cotação de'
  }.freeze

  def initialize(cotacao:, nome_corretora:)
    @cotacao = cotacao
    @nome_corretora = nome_corretora.to_s
  end

  # -> os bytes do PDF (`%PDF-`).
  def render
    @doc = Prawn::Document.new(page_size: 'A4', page_layout: :landscape, margin: MARGEM,
                               info: { Title: TEXTOS[:titulo] })
    registrar_fontes
    cabecalho
    tabela
    rodape
    @doc.render
  end

  private

  def planos
    @planos ||= @cotacao.planos.to_a
  end

  def pedido
    @pedido ||= @cotacao.pedido.to_h
  end

  def registrar_fontes
    @doc.font_families.update(
      'Inter' => { normal: FONTES.join('Inter-Regular.ttf').to_s, medium: FONTES.join('Inter-Medium.ttf').to_s,
                   semibold: FONTES.join('Inter-SemiBold.ttf').to_s, bold: FONTES.join('Inter-Bold.ttf').to_s }
    )
    @doc.font 'Inter'
  end

  def cabecalho
    @doc.fill_color COR[:navy]
    @doc.text @nome_corretora, size: 11, style: :semibold unless @nome_corretora.empty?
    @doc.text TEXTOS[:titulo], size: 18, style: :bold
    @doc.move_down 6
    @doc.fill_color COR[:tinta]
    linhas_do_pedido.each { |rotulo, valor| @doc.text "#{rotulo}: #{valor}", size: 9.5 }
    @doc.move_down 12
  end

  def linhas_do_pedido
    [[TEXTOS[:destinos], pedido['destinos'].to_a.join(', ')],
     [TEXTOS[:datas], "#{data(pedido['data_saida'])} a #{data(pedido['data_retorno'])}"],
     [TEXTOS[:viajantes], @cotacao.idades.map { |idade| "#{idade} #{idade == 1 ? 'ano' : 'anos'}" }.join(', ')]]
  end

  def tabela
    linhas = [cabecalho_da_tabela, linha_total, linha_por_pessoa, linha_parcelas, *linhas_de_coberturas]
    @doc.table(linhas, header: true, width: @doc.bounds.width, column_widths: larguras,
                       cell_style: { size: 8.5, padding: [5, 6], borders: [:bottom], border_width: 0.5,
                                     border_color: COR[:linha], text_color: COR[:tinta] }) do |tabela|
      tabela.row(0).style(background_color: COR[:navy], text_color: COR[:branco], font_style: :semibold)
      tabela.column(0).style(font_style: :medium)
    end
  end

  def larguras
    resto = (@doc.bounds.width - LARGURA_DO_ROTULO) / [planos.size, 1].max
    [LARGURA_DO_ROTULO, *Array.new(planos.size, resto)]
  end

  def cabecalho_da_tabela
    [TEXTOS[:plano], *planos.map { |plano| plano['nome'].to_s }]
  end

  def linha_total
    [TEXTOS[:total], *planos.map { |plano| dinheiro(plano['preco_total']) }]
  end

  def linha_por_pessoa
    [TEXTOS[:por_pessoa], *planos.map { |plano| por_pessoa(plano) }]
  end

  def por_pessoa(plano)
    precos = SeguroViagem::Faixas.precos_por_pessoa(plano, @cotacao.idades)
    precos.each_with_index.map { |preco, indice| "Viajante #{indice + 1}: #{dinheiro(preco)}" }.join("\n")
  end

  def linha_parcelas
    [TEXTOS[:parcelas], *planos.map { |plano| plano['max_parcelas'].present? ? "até #{plano['max_parcelas']}x" : SEM_VALOR }]
  end

  # Uma linha por cobertura, pela união dos `id_beneficio` na ordem em que aparecem; "—" onde o plano não a tem.
  def linhas_de_coberturas
    nomes = {}
    planos.each { |plano| plano['coberturas'].to_a.each { |cobertura| nomes[cobertura['id_beneficio']] ||= cobertura['nome'].to_s } }
    nomes.map do |id, nome|
      [nome, *planos.map { |plano| valor_da_cobertura(plano, id) }]
    end
  end

  def valor_da_cobertura(plano, id)
    cobertura = plano['coberturas'].to_a.find { |item| item['id_beneficio'] == id }
    cobertura.present? && cobertura['valor'].present? ? cobertura['valor'].to_s : SEM_VALOR
  end

  def rodape
    @doc.move_down 10
    @doc.fill_color COR[:apoio]
    @doc.text "#{TEXTOS[:cotado_em]} #{@cotacao.created_at.strftime('%d/%m/%Y')}", size: 8
  end

  def dinheiro(valor)
    valor.blank? ? SEM_VALOR : SeguroViagem::Dinheiro.brl(valor)
  end

  def data(texto)
    Date.iso8601(texto.to_s).strftime('%d/%m/%Y')
  rescue Date::Error
    texto.to_s
  end
end
