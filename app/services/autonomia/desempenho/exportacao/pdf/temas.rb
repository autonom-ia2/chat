# Páginas de temas do PDF (#2226): do que as pessoas falam e o que pediram. À esquerda o ranking dos temas (top 12),
# à direita os cortes do pedido ("o que pediram" e os detalhes da ficha) empilhados enquanto cabem, com a linha de
# quantos fecharam. Os cortes que não cabem seguem em páginas próprias, três por página.
module Autonomia::Desempenho::Exportacao::Pdf::Temas
  LIMITE_DO_RANKING = 12
  CORTES_POR_PAGINA = 3
  ALTURA_UTIL = 400 # área útil abaixo do título da página
  TITULO_DO_BLOCO = 29
  VAO_ENTRE_CORTES = 12

  def paginas_de_temas
    1 + ((cortes_extras.size + CORTES_POR_PAGINA - 1) / CORTES_POR_PAGINA)
  end

  def pagina_temas(pagina)
    cima = abrir_pagina(t('temas.titulo'), t('temas.subtitulo'), pagina)
    return pagina_de_cortes(cortes_extras.each_slice(CORTES_POR_PAGINA).to_a[pagina[:parte] - 2], cima) if pagina[:parte] > 1

    metade = (largura - 20) / 2.0
    bloco_de_temas(0, cima, metade)
    cortes_da_primeira_pagina.reduce(cima) { |topo, corte| bloco_de_corte(corte, metade + 20, topo, metade) - VAO_ENTRE_CORTES }
  end

  private

  # Os cortes que cabem empilhados à direita da primeira página (sempre ao menos o primeiro).
  def cortes_da_primeira_pagina
    usado = 0
    cortes = Array(@painel['cortes'])
    cortes.each_with_index.take_while do |corte, index|
      usado += altura_do_corte(corte) + VAO_ENTRE_CORTES
      index.zero? || usado <= ALTURA_UTIL
    end.map(&:first)
  end

  def altura_do_corte(corte)
    TITULO_DO_BLOCO + ([Array(corte['ranking']).size, LIMITE_DO_RANKING].min * Autonomia::Desempenho::Exportacao::Pdf::Ranking::LINHA_COM_EXTRA)
  end

  def cortes_extras
    Array(@painel['cortes']).drop(cortes_da_primeira_pagina.size)
  end

  # As ressalvas da conferência dos temas ficam no topo do bloco, perto dos primeiros (que são os inflados); o ranking
  # perde as linhas que elas ocupam, para não passar do fim da página.
  def bloco_de_temas(esq, cima, largura_total)
    cima = titulo_do_bloco(t('temas.temas_titulo'), esq, cima, largura_total, descricao: t('temas.temas_descricao'))
    reservado = altura_das_ressalvas(%w[temas], largura_total)
    cima = ressalvas_da_conferencia(%w[temas], esq, cima, largura_total)
    itens = Array(@painel.dig('temas', 'ranking')).map do |tema|
      { nome: tema['nome'], valor: tema['procuras'], pct: tema['pct'], extra: extra_do_tema(tema),
        delta: (variacao_do_tema(tema) if tema['anterior_procuras']) }
    end
    limite = LIMITE_DO_RANKING - (reservado / Autonomia::Desempenho::Exportacao::Pdf::Ranking::LINHA_COM_EXTRA).ceil
    cima = ranking(itens, esq, cima, largura_total, serie: 'volume', limite: limite)
    escrever(t('temas.unidade'), esq, cima - 4, largura_total, tamanho: 6.5, tinta: :fraca)
  end

  def extra_do_tema(tema)
    partes = [frase_de_fechou('temas.fecharam', tema['fecharam'], tema['compra'], tema['taxa_pct'])]
    partes << t('temas.erro_grave', pct: pct(tema['erro_grave_pct'])) if tema['erro_grave_pct'].to_f.positive?
    partes << t('temas.mais_trava', nome: nome_de(catalogo, 'motivos', tema['motivo_principal_id'])) if trava_propria?(tema)
    partes.compact.join(' · ')
  end

  def variacao_do_tema(tema)
    diferenca = tema['procuras'].to_i - tema['anterior_procuras'].to_i
    return t('temas.igual_antes') if diferenca.zero?

    t(diferenca.positive? ? 'temas.mais_que_antes' : 'temas.menos_que_antes', n: numero(diferenca.abs))
  end

  def bloco_de_corte(corte, esq, cima, largura_total)
    cima = titulo_do_bloco(corte['nome'], esq, cima, largura_total, descricao: t('temas.corte_descricao'))
    itens = Array(corte['ranking']).map do |linha|
      { nome: linha['nome'], valor: linha['procuras'], pct: linha['pct'],
        extra: frase_de_fechou('temas.fecharam', linha['fecharam'], linha['compra'], linha['taxa_pct']) }
    end
    ranking(itens, esq, cima, largura_total, serie: 'preparo', limite: LIMITE_DO_RANKING)
  end

  def pagina_de_cortes(cortes, cima)
    cada = (largura - (20 * (CORTES_POR_PAGINA - 1))) / CORTES_POR_PAGINA.to_f
    Array(cortes).each_with_index { |corte, index| bloco_de_corte(corte, index * (cada + 20), cima, cada) }
  end
end
