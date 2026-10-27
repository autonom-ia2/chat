# Página 03 do PDF (#2226): até onde as procuras chegam. Cartões dos marcos (o 1º na cor de volume, os do meio de
# preparo, o último de resultado) ligados por conector; embaixo deles, por que o último passo e o resultado não dão o
# mesmo número (a conciliação); depois as comparações A × B ("o que muda o resultado"), uma por linha na largura toda,
# com a ressalva de cada uma. A razão "N× mais" e os pontos saem da conta exata (n/m de cada lado), igual à tela.
module Autonomia::Desempenho::Exportacao::Pdf::Funil
  ALTURA_DA_ETAPA = 84
  VAO_DA_ETAPA = 16
  ALTURA_DA_COMPARACAO = 50
  MEIO_DA_COMPARACAO = 150
  ROTULO_DA_COMPARACAO = 150
  VEZES_MINIMAS = 1.5
  # Uma comparação A × B só vale com pelo menos isto de base em cada lado, igual à tela (MINIMO_DO_DESTAQUE).
  MINIMO_DA_COMPARACAO = 20

  def pagina_funil(_pagina)
    cima = abrir_pagina(t('funil.titulo'), t('funil.subtitulo'))
    cima = etapas_do_funil(Array(@painel.dig('funil', 'etapas')).first(6), cima)
    nota = @painel.dig('funil', 'nota')
    escrever(nota, 0, cima - 6, largura, tamanho: 7.5, tinta: :apoio) if nota.present?
    cima = conciliacao_do_funil(cima - 20)
    comparacoes_do_funil(0, cima - 14, largura)
  end

  private

  def etapas_do_funil(etapas, cima)
    return vazio(0, cima, largura) if etapas.empty?

    cada = (largura - (VAO_DA_ETAPA * (etapas.size - 1))) / etapas.size.to_f
    etapas.each_with_index do |etapa, index|
      esq = index * (cada + VAO_DA_ETAPA)
      cartao_da_etapa(etapa, [esq, cima, cada], cor_da_etapa(index, etapas.size), primeira: index.zero?)
      conector(esq + cada, cima - (ALTURA_DA_ETAPA / 2.0)) if index < etapas.size - 1
    end
    cima - ALTURA_DA_ETAPA
  end

  def cor_da_etapa(index, total)
    return 'volume' if index.zero?

    index == total - 1 ? 'resultado' : 'preparo'
  end

  # caixa = [esq, cima, largura].
  def cartao_da_etapa(etapa, caixa, cor_da_serie, primeira:)
    esq, cima, cada = caixa
    cartao(esq, cima, cada, ALTURA_DA_ETAPA, fundo: serie(cor_da_serie, :trilho), borda: serie(cor_da_serie, :trilho))
    faixa(esq + 6, cima, cada - 12, 3, serie(cor_da_serie))
    anterior = t('funil.da_anterior', pct: pct(etapa['taxa_da_anterior'])) unless primeira || etapa['taxa_da_anterior'].nil?
    escrever_pilha([[etapa['nome'], 9, { tamanho: 8, estilo: :semibold, tinta: serie(cor_da_serie, :texto), altura: 11 }],
                    [numero(etapa['procuras']), 22, { tamanho: 24, estilo: :bold, altura: 27 }],
                    [t('funil.do_inicio', pct: pct(etapa['pct_do_inicio'])), 52, { tamanho: 7, tinta: :apoio, altura: 10 }],
                    [anterior, 64, { tamanho: 7, tinta: :apoio, altura: 10 }]], esq + 10, cima, cada - 20)
  end

  def conector(esq, altura)
    linha_fina(esq + 2, esq + VAO_DA_ETAPA - 2, altura)
    @doc.fill_color cor(:fraca)
    @doc.fill_circle [esq + (VAO_DA_ETAPA / 2.0), altura], 2
  end

  def conciliacao_do_funil(cima)
    texto = frase_da_conciliacao
    texto ? ressalva(texto, 0, cima, largura) : cima
  end

  # "Por que “Gerou o link” (13) e “Fecharam” (17) não dão o mesmo número: 1 chegou a este passo e não terminou em
  # “Fecharam”; 5 terminaram em “Fecharam” sem passar por este passo." Igual à tela.
  def frase_da_conciliacao
    dados = @painel.dig('funil', 'conciliacao')
    ultima = Array(@painel.dig('funil', 'etapas')).last
    return nil if dados.blank? || ultima.nil?

    fechou = nomes['fechou'].to_s
    partes = partes_da_conciliacao(dados, fechou)
    return t('funil.conciliacao_igual', etapa: ultima['nome'], fechou: fechou) if partes.empty?

    t('funil.conciliacao', etapa: ultima['nome'], a: numero(dados['chegaram_ao_fim']), fechou: fechou, b: numero(dados['fecharam']),
                           partes: partes.join('; '))
  end

  def partes_da_conciliacao(dados, fechou)
    { 'chegaram_e_nao_fecharam' => 'funil.conciliacao_nao_fecharam', 'fecharam_sem_chegar' => 'funil.conciliacao_fora' }.filter_map do |campo, chave|
      quantas = dados[campo].to_i
      t(chave, count: quantas, n: numero(quantas), fechou: fechou) if quantas.positive?
    end
  end

  def comparacoes_do_funil(esq, cima, largura_total)
    cima = titulo_do_bloco(t('funil.comparacoes_titulo'), esq, cima, largura_total, descricao: t('funil.comparacoes_descricao'))
    Array(@painel['comparacoes']).first(3).each { |comparacao| cima = cartao_de_comparacao(comparacao, esq, cima, largura_total) - 8 }
  end

  # Uma linha: o recorte à esquerda, o lado A, a diferença no meio e o lado B.
  def cartao_de_comparacao(comparacao, esq, cima, largura_total)
    cartao(esq, cima, largura_total, ALTURA_DA_COMPARACAO)
    escrever(t("funil.recorte.#{comparacao['recorte']}", default: t('funil.recorte.outro')), esq + 12, cima - 19,
             ROTULO_DA_COMPARACAO - 20, tamanho: 9, estilo: :semibold)
    coluna = (largura_total - ROTULO_DA_COMPARACAO - MEIO_DA_COMPARACAO - 20) / 2.0
    lados_da_comparacao(comparacao, esq + ROTULO_DA_COMPARACAO, cima + 12, coluna)
    cima -= ALTURA_DA_COMPARACAO
    comparacao['ressalva'].present? ? ressalva(comparacao['ressalva'], esq, cima - 4, largura_total, tamanho: 7) : cima
  end

  # Com poucos casos, o lado A não ganha a cor de destaque (igual à tela).
  def lados_da_comparacao(comparacao, esq, cima, coluna)
    poucos = comparacao_fraca?(comparacao)
    lado_da_comparacao(comparacao['a'], [esq, cima - 19, coluna], poucos ? 'neutro' : 'resultado')
    escrever(diferenca_da_comparacao(comparacao), esq + coluna, cima - 26, MEIO_DA_COMPARACAO,
             tamanho: 8.5, estilo: :bold, alinhar: :center, tinta: serie(poucos ? 'tempo' : 'volume', :texto))
    lado_da_comparacao(comparacao['b'], [esq + coluna + MEIO_DA_COMPARACAO, cima - 19, coluna], 'neutro')
  end

  def lado_da_comparacao(lado, caixa, cor_da_serie)
    lado = lado.to_h
    escrever_pilha([[pct(lado['pct']), 0, { tamanho: 15, estilo: :bold, tinta: serie(cor_da_serie, :texto), altura: 18 }],
                    [t('funil.n_de_m', n: numero(lado['n']), m: numero(lado['m'])), 19, { tamanho: 7, tinta: :apoio }],
                    [lado['nome'], 29, { tamanho: 7.5, estilo: :semibold, altura: 10 }]], *caixa)
  end

  def comparacao_fraca?(comparacao)
    [comparacao['a'], comparacao['b']].any? { |lado| lado.to_h['m'].to_i < MINIMO_DA_COMPARACAO }
  end

  # "7,4× mais" e "2,1 pontos a mais/a menos" pela conta exata (n/m de cada lado), arredondando só no fim, nunca dos %
  # já arredondados. Lado com menos de MINIMO_DA_COMPARACAO: "Poucos casos para comparar", igual à tela.
  def diferenca_da_comparacao(comparacao)
    a = comparacao['a'].to_h
    b = comparacao['b'].to_h
    return '' if a['pct'].nil? || b['pct'].nil?
    return t('funil.sem_comparar') if comparacao_fraca?(comparacao)

    vezes = vezes_da_comparacao(a, b)
    return t('funil.vezes', n: decimal(vezes)) if vezes && vezes >= VEZES_MINIMAS

    pontos_da_comparacao(((taxa_exata(a) - taxa_exata(b)) * 100).to_f.round(1))
  end

  def taxa_exata(lado)
    lado['n'].to_r / lado['m']
  end

  def vezes_da_comparacao(lado, outro)
    taxa_do_outro = taxa_exata(outro)
    taxa_do_outro.positive? ? (taxa_exata(lado) / taxa_do_outro).to_f : nil
  end

  def pontos_da_comparacao(pontos)
    return t('funil.igual') if pontos.zero?

    t(pontos.positive? ? 'funil.pontos_a_mais' : 'funil.pontos_a_menos', n: decimal(pontos.abs))
  end
end
