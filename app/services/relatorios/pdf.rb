# Base dos relatórios em PDF (#1960): A4 deitado (material de painel), letra Inter embutida e o visual da plataforma.
# Blocos prontos para qualquer relatório montar as páginas:
# - capa (Pdf::Capa): faixa azul-escura de ponta a ponta com a conta, o período e a frase do relatório;
# - cabecalho: o topo das páginas de dentro (relatório e período, com uma linha fina);
# - kpis e funil (Pdf::Numeros): cartões de número com sombra suave (o de destaque em verde) e as etapas em barras
#   que encolhem, com o número dentro e a parte do todo ao lado;
# - ranking e pessoas (Pdf::Listas): linhas com foto, nome, detalhe e valor; linhas com nome, detalhe e um selo
#   colorido da situação, em uma ou duas colunas;
# - grafico (Pdf::Grafico): barras por dia com linhas de guia e o maior valor marcado;
# - foto (Pdf::Foto): imagem com cantos arredondados (ou bloco de cor com o nome, sem imagem);
# - titulo_de_secao, nota e chamada (faixa colorida com o recado mais importante).
# O rodapé (texto da esquerda e "página X de Y") sai sozinho em toda página. Coordenadas: `esquerda` a partir da
# margem esquerda, `topo` a partir da base da área útil (o jeito do Prawn). Cada bloco devolve o `topo` logo abaixo dele.
#
# Só Ruby (Prawn): nada de navegador no servidor. Foto entra só como PNG ou JPEG já em memória.
class Relatorios::Pdf
  include Relatorios::Pdf::Capa
  include Relatorios::Pdf::Numeros
  include Relatorios::Pdf::Listas
  include Relatorios::Pdf::Grafico
  include Relatorios::Pdf::Foto

  FONTES = Rails.root.join('lib/assets/fonts/inter').freeze
  COR = {
    heroi: '0D2344', heroi_linha: '17306B', heroi_texto: 'B8C4DA', tinta: '0F172A', suave: '475569', fraca: '94A3B8',
    linha: 'E2E8F0', fundo: 'F1F5F9', branco: 'FFFFFF', sombra: 'E5E9F0',
    verde: '0F766E', verde_fundo: 'E6F4F1', verde_borda: 'B7DED6', azul: '2563EB', azul_claro: '93C5FD', azul_fundo: 'E8F0FE',
    ambar: 'B45309', ambar_fundo: 'FDF3E3', cinza_fundo: 'EEF2F6'
  }.freeze
  TONS = {
    verde: %i[verde verde_fundo], azul: %i[azul azul_fundo], ambar: %i[ambar ambar_fundo], cinza: %i[suave cinza_fundo]
  }.freeze
  MARGEM = [36, 36, 40, 36].freeze # topo, direita, base, esquerda (pt)
  RAIO = 12
  ALTURA_DA_CHAMADA = 44

  attr_reader :doc

  def initialize(titulo:, rodape:, pagina:)
    @rodape = rodape
    @pagina = pagina
    @doc = Prawn::Document.new(page_size: 'A4', page_layout: :landscape, margin: MARGEM.dup, info: { Title: titulo })
    registrar_fontes
  end

  def gerar
    rodape
    @doc.render
  end

  def nova_pagina
    @doc.start_new_page
  end

  def largura
    @doc.bounds.width
  end

  def altura
    @doc.bounds.height
  end

  def cor(chave)
    COR.fetch(chave)
  end

  def cabecalho(titulo:, periodo:)
    @doc.fill_color cor(:suave)
    @doc.text_box titulo, at: [0, altura], width: largura / 2, size: 9, style: :semibold
    @doc.text_box periodo, at: [largura / 2, altura], width: largura / 2, size: 9, align: :right
    separador(0, altura - 16, largura)
    altura - 32
  end

  def titulo_de_secao(texto, topo:, esquerda: 0, largura_total: largura, nota: nil)
    @doc.fill_color cor(:tinta)
    @doc.text_box texto, at: [esquerda, topo], width: largura_total, size: 13, style: :semibold
    return topo - 26 if nota.blank?

    @doc.fill_color cor(:suave)
    @doc.text_box nota, at: [esquerda, topo - 19], width: largura_total, size: 9.5
    topo - 42
  end

  def nota(texto, topo:, esquerda: 0, largura_total: largura, tamanho: 9)
    @doc.fill_color cor(:suave)
    @doc.text_box texto, at: [esquerda, topo], width: largura_total, size: tamanho
    topo - 16
  end

  # Faixa com o fundo do tom e um ponto de cor: o recado que a pessoa não pode deixar passar.
  def chamada(texto, topo:, tom: :ambar, esquerda: 0, largura_total: largura)
    tinta, fundo = TONS.fetch(tom).map { |chave| cor(chave) }
    @doc.fill_color fundo
    @doc.fill_rounded_rectangle([esquerda, topo], largura_total, ALTURA_DA_CHAMADA, RAIO)
    @doc.fill_color tinta
    @doc.fill_circle [esquerda + 22, topo - (ALTURA_DA_CHAMADA / 2)], 5
    @doc.text_box texto, at: [esquerda + 38, topo], width: largura_total - 54, height: ALTURA_DA_CHAMADA, size: 11,
                         style: :semibold, valign: :center, overflow: :shrink_to_fit
    topo - ALTURA_DA_CHAMADA
  end

  private

  def separador(esquerda, topo, largura_total)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line esquerda, esquerda + largura_total, at: topo
  end

  def registrar_fontes
    @doc.font_families.update(
      'Inter' => {
        normal: FONTES.join('Inter-Regular.ttf').to_s, medium: FONTES.join('Inter-Medium.ttf').to_s,
        semibold: FONTES.join('Inter-SemiBold.ttf').to_s, bold: FONTES.join('Inter-Bold.ttf').to_s
      }
    )
    @doc.font 'Inter'
  end

  # Texto da esquerda em cada página (o text_box abaixo da área útil precisa de altura própria) e "página X de Y".
  def rodape
    (1..@doc.page_count).each do |numero|
      @doc.go_to_page(numero)
      @doc.fill_color cor(:fraca)
      @doc.text_box @rodape, at: [0, -16], width: largura / 2, height: 12, size: 8
    end
    @doc.number_pages @pagina, at: [largura / 2, -16], width: largura / 2, align: :right, size: 8, color: cor(:fraca)
  end
end
