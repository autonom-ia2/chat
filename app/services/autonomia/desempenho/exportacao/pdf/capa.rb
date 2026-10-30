# Página 01 do PDF (#2226): capa-índice. Os 8 números (barra lateral na cor da série, rótulo, número, explicação
# e a comparação com o período anterior), as ressalvas da conferência que valem para eles, as leituras rápidas (só o
# que os números não dizem), a ressalva do resultado e as pílulas do índice.
module Autonomia::Desempenho::Exportacao::Pdf::Capa
  ALTURA_DO_KPI = 86
  ALTURA_DA_LEITURA = 58
  VAO = 10
  INDICE = %i[evolucao funil temas origem horarios qualidade pessoa perdas acoes como_ler].freeze
  TABELAS = %i[tabela_periodo tabela_tema tabela_regras tabela_perdas tabela_ativas].freeze

  def pagina_capa(_pagina)
    cima = abrir_pagina(t('capa.titulo'), subtitulo_da_capa)
    cima = grade_de_kpis(cima)
    cima = ressalvas_da_conferencia(%w[kpis], 0, cima - 8, largura, tamanho: 7)
    cima = grade_de_leituras(cima - 6)
    cima = ressalva(nomes['fechou_ressalva'], 0, cima - 10, largura) if nomes['fechou_ressalva'].present?
    cima = indice(cima - 14)
    escrever(t('capa.so_no_excel'), 0, cima - 8, largura, tamanho: 7.5, tinta: :apoio)
  end

  private

  # O fuso aparece uma vez no arquivo, aqui: todas as datas e horas das outras páginas estão nele.
  def subtitulo_da_capa
    t('capa.subtitulo', fuso: fuso_da_conta(meta['fuso']))
  end

  def quarto
    (largura - (3 * VAO)) / 4.0
  end

  def grade_de_kpis(cima)
    numeros_do_painel.each_with_index do |item, index|
      linha, coluna = index.divmod(4)
      cartao_kpi(item, coluna * (quarto + VAO), cima - (linha * (ALTURA_DO_KPI + VAO)))
    end
    cima - (2 * ALTURA_DO_KPI) - VAO
  end

  def cartao_kpi(item, esq, cima)
    cartao(esq, cima, quarto, ALTURA_DO_KPI)
    @doc.fill_color serie(item[:cor])
    @doc.fill_rounded_rectangle([esq, cima], 4, ALTURA_DO_KPI, 2)
    escrever_pilha([[item[:rotulo], 9, { tamanho: 8, estilo: :semibold, tinta: :apoio, altura: 11 }],
                    [item[:valor], 22, { tamanho: 24, estilo: :bold, altura: 27 }],
                    [item[:explicacao], 51, { tamanho: 7, tinta: :apoio, altura: 18 }],
                    [item[:delta], 71, { tamanho: 7, estilo: :semibold, tinta: tinta_do_delta(item[:sentido]), altura: 10 }]],
                   esq + 14, cima, quarto - 22)
  end

  def tinta_do_delta(sentido)
    { favoravel: serie('resultado', :texto), desfavoravel: serie('alerta', :texto) }.fetch(sentido, cor(:apoio))
  end

  def grade_de_leituras(cima)
    leituras = leituras_rapidas(negrito: ->(texto) { "<b>#{texto}</b>" }, escapar: ->(texto) { CGI.escapeHTML(texto) })
    cada = (largura - (VAO * (leituras.size - 1))) / [leituras.size, 1].max.to_f
    leituras.each_with_index do |leitura, index|
      esq = index * (cada + VAO)
      cartao(esq, cima, cada, ALTURA_DA_LEITURA, fundo: :fundo, borda: :fundo)
      escrever_pilha([[leitura[:titulo], 8, { tamanho: 8, estilo: :semibold, altura: 11 }],
                      [leitura[:texto], 22, { tamanho: 8, altura: 32, formatado: true }]], esq + 10, cima, cada - 20)
    end
    cima - ALTURA_DA_LEITURA
  end

  # "Evolução 02 · Funil 03 · … · Tabelas 13–NN", em pílulas.
  def indice(cima)
    escrever(t('capa.indice'), 0, cima, largura, tamanho: 8, estilo: :semibold, tinta: :apoio)
    itens_do_indice.reduce(0) do |esq, (rotulo, paginas)|
      esq + pilula("#{rotulo}  #{paginas}", esq, cima - 14, fundo: cor(:fundo), tinta: cor(:tinta), tamanho: 8) + 6
    end
    cima - 30
  end

  def itens_do_indice
    itens = INDICE.map { |secao| [t("indice.#{secao}"), faixa_de_paginas(*paginas_da_secao(secao))] }
    tabelas = TABELAS.map { |secao| paginas_da_secao(secao) }.select(&:first)
    itens << [t('indice.tabelas'), faixa_de_paginas(tabelas.first.first, tabelas.last.last)] if tabelas.any?
    itens
  end

  def faixa_de_paginas(primeira, ultima)
    return format('%02d', primeira) if primeira == ultima

    "#{format('%02d', primeira)}–#{format('%02d', ultima)}"
  end
end
