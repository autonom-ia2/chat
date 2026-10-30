# Ranking do PDF do painel de desempenho (#2226): uma linha por item, rótulo | trilho | valor + %, e embaixo o texto
# extra e a variação. Usa as peças de Desenho (escrever, barra, reticências, vazio).
module Autonomia::Desempenho::Exportacao::Pdf::Ranking
  LINHA_DO_RANKING = 17
  LINHA_COM_EXTRA = 27
  VALOR_DO_RANKING = 70
  DELTA_DO_RANKING = 92

  # itens: [{ nome:, valor:, pct:, extra:, delta: }]; o trilho é proporcional ao maior valor da lista.
  # Opções: serie (padrão 'neutro') e limite (padrão 8).
  def ranking(itens, esq, cima, largura, **opcoes)
    lista = Array(itens).first(opcoes.fetch(:limite, 8))
    return vazio(esq, cima, largura) if lista.empty?

    contexto = { esq: esq, largura: largura, serie: opcoes.fetch(:serie, 'neutro'), maximo: [lista.pluck(:valor).compact.max.to_f, 1].max }
    lista.reduce(cima) { |topo, item| linha_do_ranking(item, topo, contexto) }
  end

  private

  def linha_do_ranking(item, cima, contexto)
    rotulo = (contexto[:largura] * 0.34).floor
    rotulo_e_trilho(item, cima, contexto, rotulo)
    escrever(valor_do_ranking(item), contexto[:esq] + contexto[:largura] - VALOR_DO_RANKING, cima - 1, VALOR_DO_RANKING,
             tamanho: 8, estilo: :semibold, alinhar: :right, altura: 10)
    return cima - LINHA_DO_RANKING if item[:extra].blank? && item[:delta].blank?

    extra_do_ranking(item, cima - 11, contexto)
    cima - LINHA_COM_EXTRA
  end

  # A linha de baixo, na largura da linha toda: o texto (cortado em "…" se não couber) e a variação (`delta`) em
  # posição fixa na ponta direita, que o corte do texto nunca alcança.
  def extra_do_ranking(item, altura, contexto)
    largura_do_extra = contexto[:largura] - (item[:delta] ? DELTA_DO_RANKING + 6 : 0)
    extra = reticencias(item[:extra], largura_do_extra, 6.5, linhas: 1)
    escrever(extra, contexto[:esq], altura, largura_do_extra, tamanho: 6.5, tinta: :apoio, altura: 9)
    return if item[:delta].blank?

    escrever(item[:delta], contexto[:esq] + contexto[:largura] - DELTA_DO_RANKING, altura, DELTA_DO_RANKING,
             tamanho: 6.5, estilo: :semibold, tinta: :apoio, alinhar: :right, altura: 9)
  end

  def rotulo_e_trilho(item, cima, contexto, rotulo)
    trilho = contexto[:largura] - rotulo - VALOR_DO_RANKING - 12
    escrever(item[:nome], contexto[:esq], cima - 1, rotulo - 6, tamanho: 8, altura: 10)
    barra(contexto[:esq] + rotulo, cima - 2.5, trilho, item[:valor].to_f / contexto[:maximo], serie: contexto[:serie], altura: 6)
  end

  def valor_do_ranking(item)
    item.key?(:pct) ? "#{numero(item[:valor])}  #{pct(item[:pct])}" : numero(item[:valor])
  end
end
