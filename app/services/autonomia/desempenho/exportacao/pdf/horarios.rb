# Página 06 do PDF (#2226): quando chegam as procuras. Mapa de calor 7 × 24 sempre com o número na célula (substitui
# o mouse da tela), coluna e linha Total, o pico com contorno, a legenda de escala e, embaixo, a tabela das 4 faixas
# (no horário comercial, fora, fim de semana, noite) com quanto fechou e quantos ficaram sem pessoa.
module Autonomia::Desempenho::Exportacao::Pdf::Horarios
  ROTULO_DO_DIA = 34
  COLUNA_TOTAL = 40
  ALTURA_DA_CELULA = 20
  VAO_DA_CELULA = 2
  TONS_DO_MAPA = %w[F0F0F3 E6F4FE CEE7FE ACD8FC 0090FF 0D74CE].freeze
  FAIXAS = %w[dentro fora fim_de_semana noite].freeze

  def pagina_horarios(_pagina)
    cima = abrir_pagina(t('horarios.titulo'), t('horarios.subtitulo'))
    mapa = Array(@painel.dig('horarios', 'mapa'))
    return vazio(0, cima, largura) if mapa.empty?

    cima = minis(0, cima, largura * 0.6, minis_dos_horarios(mapa))
    cima = mapa_de_calor(mapa, cima - 10)
    cima = legenda_do_mapa(mapa, cima - 4)
    tabela_das_faixas(cima - 12)
  end

  private

  def pico_do_mapa(mapa)
    celulas = mapa.each_with_index.flat_map { |horas, dia| horas.each_with_index.map { |valor, hora| [valor.to_i, dia, hora] } }
    celulas.max_by(&:first)
  end

  def minis_dos_horarios(mapa)
    valor, dia, hora = pico_do_mapa(mapa)
    fora = @painel.dig('horarios', 'faixas', 'fora', 'pct')
    [[numero(valor), t('horarios.pico', dia: t('dias')[dia], hora: hora)],
     [numero(@painel.dig('horarios', 'total')), t('horarios.total')],
     [pct(fora), t('horarios.fora_do_horario')]]
  end

  def largura_da_celula
    (largura - ROTULO_DO_DIA - COLUNA_TOTAL - (VAO_DA_CELULA * 25)) / 24.0
  end

  def mapa_de_calor(mapa, cima)
    _valor, dia_do_pico, hora_do_pico = pico_do_mapa(mapa)
    contexto = { maximo: [mapa.flatten.map(&:to_i).max, 1].max, pico: [dia_do_pico, hora_do_pico] }
    cabecalho_das_horas(cima)
    cima -= 12
    mapa.each_with_index { |horas, dia| linha_do_mapa(horas, dia, cima - (dia * (ALTURA_DA_CELULA + VAO_DA_CELULA)), contexto) }
    linha_total_do_mapa(mapa, cima - (7 * (ALTURA_DA_CELULA + VAO_DA_CELULA)))
  end

  def linha_do_mapa(horas, dia, cima, contexto)
    escrever(t('dias_curtos')[dia], 0, cima - 6, ROTULO_DO_DIA - 4, tamanho: 7.5, tinta: :apoio)
    horas.each_with_index { |valor, hora| celula(valor.to_i, hora, cima, contexto[:maximo], contexto[:pico] == [dia, hora]) }
    celula_total(horas.sum(&:to_i), cima)
  end

  def x_da_hora(hora)
    ROTULO_DO_DIA + (hora * (largura_da_celula + VAO_DA_CELULA))
  end

  def cabecalho_das_horas(cima)
    24.times do |hora|
      escrever(hora.to_s, x_da_hora(hora), cima, largura_da_celula, tamanho: 6.5, tinta: :fraca, alinhar: :center)
    end
    escrever(t('horarios.total'), x_da_hora(24), cima, COLUNA_TOTAL, tamanho: 6.5, tinta: :fraca, estilo: :semibold, alinhar: :center)
  end

  def tom_do_mapa(valor, maximo)
    return 0 if valor.zero?

    (1 + ((valor - 1) * 5 / maximo.to_f).floor).clamp(1, 5)
  end

  def celula(valor, hora, cima, maximo, pico)
    tom = tom_do_mapa(valor, maximo)
    @doc.fill_color TONS_DO_MAPA[tom]
    @doc.fill_rounded_rectangle([x_da_hora(hora), cima], largura_da_celula, ALTURA_DA_CELULA, 4)
    contorno_do_pico(x_da_hora(hora), cima) if pico
    return if valor.zero?

    escrever(valor.to_s, x_da_hora(hora), cima - 6.5, largura_da_celula,
             tamanho: 7, estilo: :semibold, alinhar: :center, tinta: tom >= 4 ? cor(:branco) : serie('volume', :texto))
  end

  def contorno_do_pico(esq, cima)
    @doc.stroke_color cor(:tinta)
    @doc.line_width 1.4
    @doc.stroke_rounded_rectangle([esq, cima], largura_da_celula, ALTURA_DA_CELULA, 4)
  end

  def celula_total(valor, cima)
    escrever(numero(valor), x_da_hora(24), cima - 6, COLUNA_TOTAL, tamanho: 7.5, estilo: :bold, alinhar: :center)
  end

  def linha_total_do_mapa(mapa, cima)
    escrever(t('horarios.total'), 0, cima - 6, ROTULO_DO_DIA - 4, tamanho: 7.5, estilo: :bold)
    24.times do |hora|
      soma = mapa.sum { |horas| horas[hora].to_i }
      escrever(numero(soma), x_da_hora(hora), cima - 6, largura_da_celula, tamanho: 7, estilo: :bold, alinhar: :center)
    end
    celula_total(mapa.flatten.sum(&:to_i), cima)
    cima - ALTURA_DA_CELULA
  end

  def legenda_do_mapa(mapa, cima)
    escrever(t('horarios.menos'), 0, cima, 40, tamanho: 7, tinta: :apoio)
    TONS_DO_MAPA.each_with_index do |tom, index|
      @doc.fill_color tom
      @doc.fill_rounded_rectangle([42 + (index * 16), cima + 1], 13, 9, 2)
    end
    maximo = numero(mapa.flatten.map(&:to_i).max)
    escrever(t('horarios.mais', maximo: maximo), 42 + (6 * 16) + 4, cima, 420, tamanho: 7, tinta: :apoio)
    cima - 14
  end

  def tabela_das_faixas(cima)
    faixas = @painel.dig('horarios', 'faixas').to_h
    melhor = FAIXAS.max_by { |chave| faixas.dig(chave, 'taxa_pct').to_f }
    linhas = FAIXAS.map { |chave| linha_da_faixa(chave, faixas[chave].to_h) }
    cima = tabela_simples(cabecalho_das_faixas, linhas, cima, destaque: [FAIXAS.index(melhor), 5])
    escrever(nota_do_horario_comercial, 0, cima - 8, largura, tamanho: 7.5, tinta: :apoio)
  end

  def cabecalho_das_faixas
    [t('horarios.faixa'), t('tabelas.procuras'), t('tabelas.do_total'), nomes['compra'], nomes['fechou'], t('tabelas.pct_fechou'),
     t('horarios.sem_pessoa')]
  end

  def nota_do_horario_comercial
    horario = meta['horario_comercial'].to_h
    t('horarios.comercial', dias: dias_da_semana(Array(horario['dias_semana'])), inicio: horario['inicio_hora'], fim: horario['fim_hora'])
  end

  def linha_da_faixa(chave, faixa)
    [t("horarios.faixas.#{chave}"), numero(faixa['procuras']), pct(faixa['pct']), numero(faixa['compra']),
     numero(faixa['fecharam']), pct(faixa['taxa_pct']),
     numero([faixa['precisavam_pessoa'].to_i - faixa['tiveram_pessoa'].to_i, 0].max)]
  end
end
