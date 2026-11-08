# Listas dos relatórios em PDF (#1960): o ranking (foto pequena, nome, detalhe e valor) e as pessoas (nome,
# detalhe e um selo colorido da situação), em uma ou duas colunas.
module Relatorios::Pdf::Listas
  LINHA_DO_RANKING = 52
  LADO_DA_MINIATURA = 40
  LINHA_DE_PESSOA = 34
  VAO_ENTRE_COLUNAS = 24
  ESPACO_DO_SELO = 140

  # [{ foto:, nome:, detalhe:, valor: }]
  def ranking(itens, topo:, esquerda: 0, largura_total: largura)
    itens.each_with_index do |item, index|
      alto = topo - (index * LINHA_DO_RANKING)
      linha_do_ranking(item, [esquerda, alto], largura_total)
      separador(esquerda, alto - LINHA_DO_RANKING + 6, largura_total) if index < itens.size - 1
    end
    topo - (itens.size * LINHA_DO_RANKING)
  end

  # [{ nome:, detalhe:, selo:, tom: }] em `colunas` colunas; tom é :verde, :azul, :ambar ou :cinza.
  def pessoas(itens, topo:, esquerda: 0, largura_total: largura, colunas: 2)
    cada = (largura_total - (VAO_ENTRE_COLUNAS * (colunas - 1))) / colunas
    por_coluna = (itens.size.to_f / colunas).ceil
    itens.each_with_index do |item, index|
      coluna, linha = index.divmod(por_coluna)
      pessoa(item, [esquerda + (coluna * (cada + VAO_ENTRE_COLUNAS)), topo - (linha * LINHA_DE_PESSOA)], cada)
    end
    topo - (por_coluna * LINHA_DE_PESSOA)
  end

  private

  def linha_do_ranking(item, ponto, largura_total)
    esquerda, alto = ponto
    foto(item, esquerda: esquerda, topo: alto, lado: LADO_DA_MINIATURA, miniatura: true)
    texto = largura_total - 180
    @doc.fill_color cor(:tinta)
    @doc.text_box item[:nome].to_s, at: [esquerda + 54, alto - 4], width: texto, height: 15, size: 10.5, style: :semibold,
                                    overflow: :shrink_to_fit
    @doc.fill_color cor(:suave)
    @doc.text_box item[:detalhe].to_s, at: [esquerda + 54, alto - 22], width: texto, size: 9
    @doc.fill_color cor(:verde)
    @doc.text_box item[:valor].to_s, at: [esquerda + largura_total - 120, alto - 12], width: 120, size: 12, style: :bold, align: :right
  end

  def pessoa(item, ponto, cada)
    esquerda, alto = ponto
    @doc.fill_color cor(:tinta)
    @doc.text_box item[:nome].to_s, at: [esquerda, alto - 2], width: cada - ESPACO_DO_SELO, height: 14, size: 10, style: :semibold,
                                    overflow: :shrink_to_fit
    @doc.fill_color cor(:suave)
    @doc.text_box item[:detalhe].to_s, at: [esquerda, alto - 16], width: cada - ESPACO_DO_SELO, height: 12, size: 8.5,
                                       overflow: :shrink_to_fit
    selo(item[:selo], item[:tom], [esquerda + cada, alto - 6]) if item[:selo].present?
    separador(esquerda, alto - 30, cada)
  end

  # Selo arredondado, alinhado à direita no ponto dado.
  def selo(texto, tom, ponto)
    direita, alto = ponto
    tinta, fundo = Relatorios::Pdf::TONS.fetch(tom || :cinza).map { |chave| cor(chave) }
    largura_do_texto = @doc.width_of(texto.to_s, size: 8.5, style: :semibold)
    largura_do_selo = largura_do_texto + 18
    @doc.fill_color fundo
    @doc.fill_rounded_rectangle([direita - largura_do_selo, alto], largura_do_selo, 17, 8.5)
    @doc.fill_color tinta
    @doc.text_box texto.to_s, at: [direita - largura_do_selo + 9, alto - 4.5], width: largura_do_texto + 4, size: 8.5, style: :semibold
  end
end
