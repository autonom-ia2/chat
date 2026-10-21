# Gráfico dos relatórios em PDF (#1960): barras por dia com linhas de guia; o maior dia ganha cor forte e o número em
# cima. Três datas no eixo (primeira, do meio e última).
module Relatorios::Pdf::Grafico
  ALTURA_DO_GRAFICO = 110
  RESERVA_DO_NUMERO = 16

  # `dias`: [[rótulo, valor], ...] na ordem do eixo.
  def grafico(dias, topo:, esquerda: 0, largura_total: largura, altura_do_grafico: ALTURA_DO_GRAFICO)
    base = topo - altura_do_grafico
    valores = dias.map(&:last)
    maior = [valores.max.to_i, 1].max
    guias([esquerda, base], largura_total, altura_do_grafico)
    barras(valores, [esquerda, base], largura_total / [valores.size, 1].max, (altura_do_grafico - RESERVA_DO_NUMERO).to_f / maior)
    eixo(dias.map(&:first), [esquerda, base], largura_total)
    base - 22
  end

  private

  # Cada barra ocupa 60% da sua vaga; `escala` converte o valor em altura. O primeiro maior dia leva o número.
  def barras(valores, ponto, vaga, escala)
    esquerda, base = ponto
    marcado = valores.index(valores.max) if valores.max.to_i.positive?
    valores.each_with_index do |valor, index|
      barra([esquerda + (index * vaga) + (vaga * 0.2), base], vaga * 0.6, valor * escala, index == marcado ? valor : nil)
    end
  end

  def guias(ponto, largura_total, altura_do_grafico)
    esquerda, base = ponto
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.5
    @doc.dash(2, space: 3)
    [0.5, 1].each do |fracao|
      @doc.stroke_horizontal_line esquerda, esquerda + largura_total, at: base + ((altura_do_grafico - RESERVA_DO_NUMERO) * fracao)
    end
    @doc.undash
    @doc.line_width 0.8
    @doc.stroke_horizontal_line esquerda, esquerda + largura_total, at: base
  end

  def barra(ponto, largura_da_barra, altura_da_barra, marca)
    return if altura_da_barra <= 0

    esquerda, base = ponto
    @doc.fill_color cor(marca ? :azul : :azul_claro)
    @doc.fill_rounded_rectangle([esquerda, base + altura_da_barra], largura_da_barra, altura_da_barra, [3, largura_da_barra / 2].min)
    return unless marca

    @doc.fill_color cor(:tinta)
    @doc.text_box marca.to_s, at: [esquerda - 10, base + altura_da_barra + 12], width: largura_da_barra + 20, size: 8.5, style: :bold,
                              align: :center
  end

  def eixo(rotulos, ponto, largura_total)
    esquerda, base = ponto
    @doc.fill_color cor(:suave)
    [[rotulos.first, :left], [rotulos[rotulos.size / 2], :center], [rotulos.last, :right]].uniq.each do |rotulo, lado|
      @doc.text_box rotulo.to_s, at: [esquerda, base - 6], width: largura_total, size: 8, align: lado
    end
  end
end
