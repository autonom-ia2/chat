# Página 07 do PDF (#2226): como a IA atende. À esquerda, a barra 100% (acertou, erro leve, erro grave, não atuou)
# com número e %, o tempo de resposta, a ressalva quando a conferência achou a qualidade otimista e, embaixo, os pontos
# fortes e onde mais erra (quantos couberem, até 3 cada); à direita as regras mais quebradas, com a ressalva no topo.
module Autonomia::Desempenho::Exportacao::Pdf::Qualidade
  DISTRIBUICAO = { 'acertou' => 'resultado', 'erro_leve' => 'tempo', 'erro_grave' => 'alerta', 'nao_atuou' => 'neutro' }.freeze
  LIMITE_DE_REGRAS = 10
  LIMITE_DE_TEMAS = 3
  LINHA_DE_TEMA = 26

  def pagina_qualidade(_pagina)
    cima = abrir_pagina(t('qualidade.titulo', nome: nome_do_agente), t('qualidade.subtitulo', nome: nome_do_agente))
    estreito = (largura - 20) * 0.42
    regras_quebradas(estreito + 20, cima, largura - estreito - 20)
    listas_de_temas(coluna_da_qualidade(0, cima, estreito) - 12, estreito)
  end

  private

  # Pontos fortes e onde mais erra, um embaixo do outro, com quantos couberem até o fim da página (até 3 cada).
  def listas_de_temas(cima, largura_total)
    limite = (((cima / 2.0) - 18) / LINHA_DE_TEMA).floor.clamp(1, LIMITE_DE_TEMAS)
    qualidade = @painel['qualidade'].to_h
    fim = lista_de_temas(t('qualidade.pontos_fortes'), qualidade['pontos_fortes'], [0, cima, largura_total], 'acerto', limite)
    lista_de_temas(t('qualidade.piores'), qualidade['piores_temas'], [0, fim - 8, largura_total], 'erro', limite)
  end

  def coluna_da_qualidade(esq, cima, largura_total)
    descricao = t('qualidade.como_atuou_descricao', n: numero(@painel.dig('qualidade', 'base')), nome: nome_do_agente)
    cima = titulo_do_bloco(t('qualidade.como_atuou', nome: nome_do_agente), esq, cima, largura_total, descricao: descricao)
    cima = barra_empilhada(Array(@painel.dig('qualidade', 'distribuicao')), esq, cima, largura_total)
    cima = minis(esq, cima - 8, largura_total, minis_da_qualidade, colunas: 2)
    texto = ressalva_otimista
    texto ? ressalva(texto, esq, cima - 6, largura_total) : cima
  end

  # A ressalva da conferência colada ao número: a frase fixa e, quando houver, a nota do campo.
  def ressalva_otimista
    otimista = Array(@painel.dig('confianca', 'campos')).find do |campo|
      campo['leitura'] == 'otimista' && Array(campo['afeta']).include?('qualidade')
    end
    return nil unless otimista

    [t('qualidade.otimista', pct: pct(otimista['acerto_pct'])), otimista['nota'].presence].compact.join(' ')
  end

  # A barra é a base (procuras em que o agente atuou); "não atuou" (pct nulo) fica fora dela e só aparece na legenda.
  def barra_empilhada(distribuicao, esq, cima, largura_total)
    na_base = distribuicao.reject { |item| item['pct'].nil? }
    total = [na_base.sum { |item| item['procuras'].to_i }, 1].max
    inicio = esq
    na_base.each do |item|
      comprimento = largura_total * item['procuras'].to_f / total
      faixa(inicio, cima, comprimento, 14, serie(DISTRIBUICAO.fetch(item['id'], 'neutro')))
      inicio += comprimento
    end
    legenda_empilhada(distribuicao, esq, cima - 20, largura_total)
  end

  def legenda_empilhada(distribuicao, esq, cima, largura_total)
    cada = largura_total / 2.0
    distribuicao.each_with_index do |item, index|
      linha, coluna = index.divmod(2)
      item_da_legenda(item, esq + (coluna * cada), cima - (linha * 14), cada - 14)
    end
    cima - (((distribuicao.size + 1) / 2) * 14)
  end

  def item_da_legenda(item, esq, cima, largura_total)
    @doc.fill_color serie(DISTRIBUICAO.fetch(item['id'], 'neutro'))
    @doc.fill_circle [esq + 4, cima - 4], 3.5
    parte_da_base = item['pct'].nil? ? t('qualidade.fora_da_base') : pct(item['pct'])
    escrever("#{t("qualidade.#{item['id']}")}  #{numero(item['procuras'])} · #{parte_da_base}", esq + 12, cima, largura_total, tamanho: 8)
  end

  def minis_da_qualidade
    tempo = @painel.dig('qualidade', 'tempo_resposta').to_h
    mensagens = @painel.dig('qualidade', 'mensagens').to_h
    # O "9 em cada 10 em até" já está no número do tempo de resposta da capa; aqui não se repete.
    [[segundos(tempo['mediana_seg']), t('qualidade.mediana')],
     [numero(tempo['acima_5_min']), t('qualidade.acima_5_min')],
     [decimal(mensagens['agente_por_mensagem_do_contato']), t('qualidade.mensagens_por_mensagem', nome: nome_do_agente)]]
  end

  def regras_quebradas(esq, cima, largura_total)
    cima = titulo_do_bloco(t('qualidade.regras_titulo'), esq, cima, largura_total,
                           descricao: t('qualidade.regras_descricao', nome: nome_do_agente))
    cima = ressalvas_da_conferencia(%w[regras], esq, cima, largura_total)
    itens = Array(@painel.dig('qualidade', 'regras')).map do |regra|
      extra = [regra['descricao'].presence, (t('qualidade.sistemica') if regra['sistemica'])].compact.join(' · ')
      { nome: regra['nome'], valor: regra['procuras'], pct: regra['pct'], extra: extra }
    end
    ranking(itens, esq, cima, largura_total, serie: 'alerta', limite: LIMITE_DE_REGRAS)
  end

  # caixa = [esq, cima, largura].
  def lista_de_temas(titulo, temas, caixa, tipo, limite)
    esq, cima, largura_total = caixa
    cima = titulo_do_bloco(titulo, esq, cima, largura_total)
    return vazio(esq, cima, largura_total) if Array(temas).empty?

    Array(temas).first(limite).reduce(cima) { |topo, tema| linha_de_tema(tema, tipo, [esq, topo, largura_total]) }
  end

  def linha_de_tema(tema, tipo, caixa)
    esq, cima, largura_total = caixa
    nome = largura_total * 0.4
    exemplo = Array(tema['exemplos']).first
    escrever(tema['nome'], esq, cima, nome, tamanho: 8.5, estilo: :semibold, altura: 11)
    escrever(frase_do_tema(tema, tipo), esq + nome, cima, largura_total - nome, tamanho: 8, tinta: :apoio, altura: 11)
    if exemplo
      texto = reticencias("#{prova_curta(exemplo)} — #{exemplo['resumo']}", largura_total, 7, linhas: 1)
      escrever(texto, esq, cima - 12, largura_total, tamanho: 7, tinta: :apoio, altura: 9)
    end
    cima - LINHA_DE_TEMA
  end

  def frase_do_tema(tema, tipo)
    valores = { procuras: numero(tema['procuras']), acerto: pct(tema['acerto_pct']), erro: pct(tema['erro_grave_pct']) }
    t(tipo == 'acerto' ? 'qualidade.frase_acerto' : 'qualidade.frase_erro', **valores)
  end
end
