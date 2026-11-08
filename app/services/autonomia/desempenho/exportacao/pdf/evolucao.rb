# Página 02 do PDF (#2226): como o movimento mudou. Mini-estatísticas, linha de procuras (com área), do pedido de
# compra e de quem fechou, com grade, eixo e o pico marcado; embaixo, na mesma escala, as faixas de eventos (fecharam,
# passaram para uma pessoa, ficaram sem pessoa) com bolha do tamanho da quantidade e o número em cima.
# O último ponto, se ainda em andamento, sai tracejado e com nota.
module Autonomia::Desempenho::Exportacao::Pdf::Evolucao
  EIXO = 112
  ALTURA_DO_GRAFICO = 220
  FAIXA_DE_EVENTO = 24
  MAXIMO_DE_DATAS = 7

  def pagina_evolucao(_pagina)
    cima = abrir_pagina(t('evolucao.titulo'), t("evolucao.subtitulo_#{unidade_da_evolucao}"))
    pontos = Array(@painel.dig('evolucao', 'pontos'))
    return vazio(0, cima, largura) if pontos.empty?

    cima = minis(0, cima, largura, minis_da_evolucao(pontos))
    cima = legenda_da_evolucao(cima - 10)
    cima = grafico_de_linhas(pontos, cima - 8)
    cima = faixas_de_eventos(pontos, cima - 6)
    escrever(t("evolucao.parcial_#{unidade_da_evolucao}"), 0, cima - 6, largura, tamanho: 7.5, tinta: :apoio) if pontos.last['parcial']
  end

  def unidade_da_evolucao
    @painel.dig('evolucao', 'unidade') == 'semana' ? 'semana' : 'dia'
  end

  private

  def series_da_evolucao
    [%w[procuras volume] << t('evolucao.procuras'), %w[compra preparo] << nomes['compra'],
     %w[fecharam resultado] << (nomes['fechou'].presence || t('kpi.fecharam'))]
  end

  def soma_dos_pontos(pontos, campo)
    pontos.sum { |ponto| ponto[campo].to_i }
  end

  def minis_da_evolucao(pontos)
    total = soma_dos_pontos(pontos, 'procuras')
    [[numero(total), t('evolucao.total')], mini_do_pico(pontos),
     [decimal(total.to_f / pontos.size), t("evolucao.media_#{unidade_da_evolucao}")],
     [numero(soma_dos_pontos(pontos, 'compra')), nomes['compra'].to_s],
     [numero(soma_dos_pontos(pontos, 'fecharam')), nomes['fechou'].to_s]]
  end

  def mini_do_pico(pontos)
    pico = pontos.max_by { |ponto| ponto['procuras'].to_i }
    [numero(pico['procuras']), t("evolucao.pico_#{unidade_da_evolucao}", data: dia_mes(pico['inicio']))]
  end

  def legenda_da_evolucao(cima)
    series_da_evolucao.reduce(0) do |esq, (_campo, cor_da_serie, nome)|
      @doc.fill_color serie(cor_da_serie)
      @doc.fill_circle [esq + 4, cima - 5], 3.5
      escrever(nome, esq + 11, cima - 1, 200, tamanho: 8, tinta: :apoio)
      esq + 22 + @doc.width_of(nome.to_s, size: 8)
    end
    cima - 14
  end

  def grafico_de_linhas(pontos, cima)
    teto = teto_do_eixo(pontos.pluck('procuras', 'compra', 'fecharam').flatten.compact.max.to_i)
    grade_do_grafico(cima, teto)
    escala = ->(valor) { cima - ALTURA_DO_GRAFICO + (valor.to_f / teto * ALTURA_DO_GRAFICO) }
    area_da_serie(pontos, escala, cima - ALTURA_DO_GRAFICO)
    series_da_evolucao.each { |campo, cor_da_serie, _nome| linha_da_serie(pontos, campo, cor_da_serie, escala) }
    marcar_pico(pontos, escala)
    datas_do_eixo(pontos, cima - ALTURA_DO_GRAFICO - 4)
    cima - ALTURA_DO_GRAFICO - 16
  end

  # Teto redondo (1, 2 ou 5 × 10^n) com 4 intervalos.
  def teto_do_eixo(maximo)
    return 4 if maximo <= 0

    bruto = maximo / 4.0
    potencia = 10**Math.log10(bruto).floor
    passo = [1, 2, 5, 10].find { |fator| fator * potencia >= bruto } * potencia
    (passo * 4).ceil
  end

  def x_do_ponto(index, total)
    largura_util = largura - EIXO - 10
    return EIXO + (largura_util / 2.0) if total == 1

    EIXO + (index * largura_util / (total - 1).to_f)
  end

  def grade_do_grafico(cima, teto)
    5.times do |passo|
      altura = cima - ALTURA_DO_GRAFICO + (passo * ALTURA_DO_GRAFICO / 4.0)
      linha_fina(EIXO, largura - 10, altura)
      escrever(numero((teto * passo / 4.0).round), EIXO - 40, altura + 4, 32, tamanho: 7, tinta: :fraca, alinhar: :right)
    end
  end

  def vertices(pontos, campo, escala)
    pontos.each_with_index.map { |ponto, index| [x_do_ponto(index, pontos.size), escala.call(ponto[campo])] }
  end

  def area_da_serie(pontos, escala, base)
    lista = vertices(pontos, 'procuras', escala)
    @doc.fill_color serie('volume')
    @doc.transparent(0.12) { @doc.fill_polygon([lista.first[0], base], *lista, [lista.last[0], base]) }
  end

  def linha_da_serie(pontos, campo, cor_da_serie, escala)
    lista = vertices(pontos, campo, escala)
    @doc.stroke_color serie(cor_da_serie)
    @doc.line_width campo == 'procuras' ? 2.2 : 1.6
    lista.each_cons(2).with_index { |(inicio, fim), index| segmento(inicio, fim, pontos[index + 1]['parcial']) }
    @doc.fill_color serie(cor_da_serie)
    lista.each { |vertice| @doc.fill_circle vertice, 1.8 }
  end

  def segmento(inicio, fim, tracejado)
    @doc.dash(3, space: 2) if tracejado
    @doc.stroke_line inicio, fim
    @doc.undash
  end

  def marcar_pico(pontos, escala)
    index = pontos.each_index.max_by { |posicao| pontos[posicao]['procuras'].to_i }
    altura = escala.call(pontos[index]['procuras'])
    escrever(numero(pontos[index]['procuras']), x_do_ponto(index, pontos.size) - 30, altura + 13, 60,
             tamanho: 8, estilo: :bold, alinhar: :center, tinta: serie('volume', :texto))
  end

  def datas_do_eixo(pontos, cima)
    passo = (pontos.size / MAXIMO_DE_DATAS.to_f).ceil.clamp(1, pontos.size)
    pontos.each_with_index do |ponto, index|
      next unless (index % passo).zero? || index == pontos.size - 1

      rotulo = dia_mes(ponto['inicio']) + (ponto['parcial'] ? '*' : '')
      escrever(rotulo, x_do_ponto(index, pontos.size) - 20, cima, 40, tamanho: 7, tinta: :apoio, alinhar: :center)
    end
  end

  def faixas_de_eventos(pontos, cima)
    sem_pessoa = pontos.map { |ponto| [ponto['precisavam_pessoa'].to_i - ponto['tiveram_pessoa'].to_i, 0].max }
    eventos = [[t('evolucao.evento_fecharam'), 'resultado', pontos.map { |ponto| ponto['fecharam'].to_i }],
               [t('evolucao.evento_pessoa'), 'tempo', pontos.map { |ponto| ponto['tiveram_pessoa'].to_i }],
               [t('evolucao.evento_sem_pessoa'), 'alerta', sem_pessoa]]
    eventos.reduce(cima) { |topo, evento| faixa_de_evento(evento, topo) }
  end

  def faixa_de_evento(evento, cima)
    rotulo, cor_da_serie, valores = evento
    meio = cima - (FAIXA_DE_EVENTO / 2.0) - 3
    escrever(rotulo, 0, meio + 5, EIXO - 12, tamanho: 7.5, tinta: serie(cor_da_serie, :texto), estilo: :semibold, altura: 10)
    maximo = [valores.max.to_i, 1].max
    valores.each_with_index { |valor, index| bolha(valor, [x_do_ponto(index, valores.size), meio], maximo, cor_da_serie) }
    cima - FAIXA_DE_EVENTO
  end

  def bolha(valor, centro, maximo, cor_da_serie)
    return if valor.zero?

    raio = 1.8 + (4.2 * Math.sqrt(valor / maximo.to_f))
    @doc.fill_color serie(cor_da_serie)
    @doc.fill_circle centro, raio
    escrever(numero(valor), centro[0] - 15, centro[1] + raio + 8, 30, tamanho: 6, tinta: :apoio, alinhar: :center)
  end
end
