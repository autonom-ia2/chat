# Página 09 do PDF (#2226): vendas perdidas por causa corrigível e onde travam todas as procuras. O número grande
# na cor de alerta com a parte do pedido de compra, o ranking do porquê (com exemplos) e o ranking dos motivos.
module Autonomia::Desempenho::Exportacao::Pdf::Perdas
  LIMITE_NA_TABELA = 40
  def pagina_perdas(_pagina)
    cima = abrir_pagina(t('perdas.titulo'), t('perdas.subtitulo'))
    perdas = @painel['perdas'].to_h
    cima = cabecalho_das_perdas(perdas, cima) - 8
    cima = ressalvas_da_conferencia(%w[perdas], 0, cima, largura) - 6
    metade = (largura - 24) / 2.0
    por_que_perdeu(perdas, 0, cima, metade)
    onde_travam(metade + 24, cima, metade)
  end

  # Embaixo da tabela de perdas, quando ela foi cortada: quantas mostramos e onde está a lista inteira.
  def nota_das_perdas(cima)
    total = Array(@painel.dig('perdas', 'lista')).size
    return if total <= LIMITE_NA_TABELA

    escrever(t('tabelas.tabela_perdas.so_as_primeiras', n: LIMITE_NA_TABELA, total: numero(total)), 0, cima, largura,
             tamanho: 7.5, tinta: :apoio)
  end

  private

  def cabecalho_das_perdas(perdas, cima)
    escrever(numero(perdas['total']), 0, cima, 140, tamanho: 34, estilo: :bold, tinta: serie('alerta', :texto), altura: 38)
    escrever(t('perdas.parte', pct: pct(perdas['pct_da_compra']), m: numero(@painel.dig('funil', 'base')),
                               compra: nomes['compra'].to_s.downcase), 150, cima - 4, largura - 150,
             tamanho: 11, estilo: :semibold)
    escrever(t('perdas.explicacao'), 150, cima - 21, largura - 150, tamanho: 8.5, tinta: :apoio)
    cima - 42
  end

  def por_que_perdeu(perdas, esq, cima, largura_total)
    cima = titulo_do_bloco(t('perdas.por_que'), esq, cima, largura_total, descricao: t('perdas.por_que_descricao'))
    itens = Array(perdas['por_motivo']).map do |motivo|
      { nome: motivo['nome'], valor: motivo['procuras'], pct: parte(motivo['procuras'], perdas['total']) }
    end
    cima = ranking(itens, esq, cima, largura_total, serie: 'alerta', limite: 5) - 10
    exemplos_de_perda(perdas['lista'], esq, titulo_do_bloco(t('perdas.exemplos'), esq, cima, largura_total), largura_total)
  end

  # Cada exemplo: a conversa e o porquê em até 2 linhas (o resumo inteiro fica na planilha).
  def exemplos_de_perda(lista, esq, cima, largura_total)
    Array(lista).first(2).reduce(cima) do |topo, prova|
      por_que = reticencias(prova['por_que'].presence || prova['resumo'], largura_total, 7)
      escrever_pilha([[prova_curta(prova), 0, { tamanho: 7.5, estilo: :semibold, tinta: serie('volume', :texto) }],
                      [por_que, 10, { tamanho: 7, tinta: :apoio, altura: 18 }]], esq, topo, largura_total)
      topo - 30
    end
  end

  def onde_travam(esq, cima, largura_total)
    motivos = @painel['motivos'].to_h
    descricao = t('perdas.onde_travam_descricao', compra: nomes['compra'].to_s.downcase)
    cima = titulo_do_bloco(t('perdas.onde_travam'), esq, cima, largura_total, descricao: descricao)
    itens = Array(motivos['ranking']).map { |motivo| { nome: motivo['nome'], valor: motivo['procuras'], pct: motivo['pct'] } }
    cima = ranking(itens, esq, cima, largura_total, serie: 'neutro', limite: 7)
    escrever(t('perdas.base_motivos', n: numero(motivos['com_motivo']), m: numero(motivos['base'])), esq, cima - 4, largura_total,
             tamanho: 7, tinta: :apoio)
  end
end
