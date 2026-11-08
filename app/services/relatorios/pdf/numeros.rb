# Números dos relatórios em PDF (#1960): cartões lado a lado (kpis) e o funil, as etapas em barras que encolhem.
module Relatorios::Pdf::Numeros
  ALTURA_DO_CARTAO = 92
  VAO_ENTRE_CARTOES = 12
  ETAPA_DO_FUNIL = 46
  ALTURA_DA_BARRA = 34
  ROTULO_DO_FUNIL = 160
  BARRA_MINIMA = 120
  # Cor de cada etapa antes da última (que é sempre verde).
  CORES_DO_FUNIL = %i[heroi azul].freeze

  # [{ rotulo:, valor:, nota:, destaque: }] lado a lado; o de destaque fica verde.
  def kpis(itens, topo:, esquerda: 0, largura_total: largura)
    cada = (largura_total - (VAO_ENTRE_CARTOES * (itens.size - 1))) / itens.size
    itens.each_with_index { |item, index| kpi(item, esquerda + (index * (cada + VAO_ENTRE_CARTOES)), topo, cada) }
    topo - ALTURA_DO_CARTAO
  end

  # [{ rotulo:, valor:, parte:, nota: }]: `parte` (0..1) é o tamanho da barra; a última etapa fica verde.
  def funil(etapas, topo:, esquerda: 0, largura_total: largura)
    etapas.each_with_index do |etapa, index|
      tinta = index == etapas.size - 1 ? :verde : CORES_DO_FUNIL.fetch(index, :azul)
      etapa_do_funil(etapa, [esquerda, topo - (index * ETAPA_DO_FUNIL)], largura_total, cor(tinta))
    end
    topo - (etapas.size * ETAPA_DO_FUNIL)
  end

  private

  def kpi(item, esquerda, topo, cada)
    cartao([esquerda, topo], cada, item[:destaque])
    textos_do_kpi(item, [esquerda + 16, topo], cada - 32)
  end

  def textos_do_kpi(item, ponto, texto)
    esquerda, topo = ponto
    @doc.fill_color cor(item[:destaque] ? :verde : :suave)
    @doc.text_box item[:rotulo], at: [esquerda, topo - 16], width: texto, size: 10, style: :semibold
    @doc.fill_color cor(item[:destaque] ? :verde : :tinta)
    @doc.text_box item[:valor].to_s, at: [esquerda, topo - 34], width: texto, height: 34, size: 28, style: :bold,
                                     overflow: :shrink_to_fit
    return if item[:nota].blank?

    @doc.fill_color cor(:suave)
    @doc.text_box item[:nota], at: [esquerda, topo - 72], width: texto, height: 14, size: 9, overflow: :shrink_to_fit
  end

  # Sombra deslocada para baixo e o cartão por cima, com borda fina.
  def cartao(ponto, cada, destaque)
    @doc.fill_color cor(:sombra)
    @doc.fill_rounded_rectangle([ponto[0] + 1, ponto[1] - 3], cada, ALTURA_DO_CARTAO, Relatorios::Pdf::RAIO)
    @doc.fill_color cor(destaque ? :verde_fundo : :branco)
    @doc.stroke_color cor(destaque ? :verde_borda : :linha)
    @doc.line_width 0.8
    @doc.fill_and_stroke_rounded_rectangle(ponto, cada, ALTURA_DO_CARTAO, Relatorios::Pdf::RAIO)
  end

  def etapa_do_funil(etapa, ponto, largura_total, tinta)
    trilho = largura_total - ROTULO_DO_FUNIL
    comprimento = [trilho * etapa[:parte].to_f, BARRA_MINIMA].max
    @doc.fill_color cor(:fundo)
    @doc.fill_rounded_rectangle(ponto, trilho, ALTURA_DA_BARRA, 9)
    @doc.fill_color tinta
    @doc.fill_rounded_rectangle(ponto, comprimento, ALTURA_DA_BARRA, 9)
    @doc.fill_color cor(:branco)
    @doc.text_box etapa[:valor].to_s, at: [ponto[0] + 14, ponto[1] - 9], width: comprimento - 20, size: 13, style: :bold
    rotulo_do_funil(etapa, [ponto[0] + trilho + 14, ponto[1]])
  end

  def rotulo_do_funil(etapa, ponto)
    @doc.fill_color cor(:tinta)
    @doc.text_box etapa[:rotulo].to_s, at: [ponto[0], ponto[1] - 3], width: ROTULO_DO_FUNIL - 14, size: 10.5, style: :semibold
    @doc.fill_color cor(:suave)
    @doc.text_box etapa[:nota].to_s, at: [ponto[0], ponto[1] - 19], width: ROTULO_DO_FUNIL - 14, size: 8.5
  end
end
