# Paginação das tabelas do PDF (#2226) pela altura: mede cada linha na largura real e corta a fatia quando passa da
# altura livre da página ou do teto de linhas (POR_PAGINA). Assim a tabela nunca transborda para uma página sem
# moldura e rodapé, que o plano de páginas não contaria.
module Autonomia::Desempenho::Exportacao::Pdf::Fatias
  RESERVA = 36 # abaixo da tabela: linha de total e nota do período em andamento
  TITULO = 50 # altura do título e do subtítulo da página (ver abrir_pagina)

  private

  def fatias_da_tabela(secao)
    @fatias_da_tabela ||= {}
    @fatias_da_tabela[secao] ||= fatiar(secao, linhas_da_tabela(secao))
  end

  def fatiar(secao, linhas)
    return [] if linhas.empty?

    documento

    medida = montar_tabela(cabecalho_da_tabela(secao), linhas.pluck(:celulas), opcoes_da_secao(secao))
    livre = topo - TITULO - RESERVA - medida.row(0).height
    alturas = linhas.each_index.map { |index| medida.row(index + 1).height }
    agrupar_por_altura(linhas.zip(alturas), livre, Autonomia::Desempenho::Exportacao::Pdf::Tabelas::POR_PAGINA[secao])
  end

  def agrupar_por_altura(linhas_e_alturas, livre, teto)
    fatias = [[]]
    usado = 0
    linhas_e_alturas.each do |linha, altura|
      if fatias.last.any? && (usado + altura > livre || fatias.last.size >= teto)
        fatias << []
        usado = 0
      end
      fatias.last << linha
      usado += altura
    end
    fatias
  end
end
