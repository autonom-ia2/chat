# Textos e números dos arquivos do painel de desempenho (#2226), iguais no PDF e na planilha.
# A moldura sai do I18n do Rails (`autonomia.desempenho2.c.*`, no idioma de quem chama); os nomes do negócio
# (temas, marcos, resultados, o que conta como compra e como fechou) saem do contrato, nunca daqui.
module Autonomia::Desempenho::Exportacao::Textos
  ESCOPO = 'autonomia.desempenho2.c'.freeze
  MOEDAS = { 'BRL' => 'R$', 'USD' => 'US$', 'EUR' => '€' }.freeze
  TRACO = '—'.freeze
  # Frases fixas de "o que estes números não provam" (ESPEC 2.10), iguais no PDF e na planilha.
  NAO_PROVAM = %w[assunto venda_fora anuncio audio andamento].freeze
  MINIMO_DA_TAXA = 5

  def t(chave, **valores)
    I18n.t("#{ESCOPO}.#{chave}", **valores)
  end

  def numero(valor)
    return TRACO if valor.nil?

    ActiveSupport::NumberHelper.number_to_delimited(valor, delimiter: t('formato.milhar'), separator: t('formato.decimal'))
  end

  def decimal(valor, casas = 1)
    return TRACO if valor.nil?

    ActiveSupport::NumberHelper.number_to_rounded(valor, precision: casas, delimiter: t('formato.milhar'),
                                                         separator: t('formato.decimal'))
  end

  def pct(valor)
    valor.nil? ? TRACO : "#{decimal(valor)}%"
  end

  # Parte do todo com 1 casa (0 a 100), ou nil quando a base é zero: nunca 0 no lugar de "não dá para calcular".
  def parte(numerador, base)
    return nil if base.to_f.zero?

    (numerador.to_f * 100 / base).round(1)
  end

  # Igual à tela: 45 → "45 s", 70 → "1 min 10 s", 120 → "2 min", 5400 → "1,5 h". Nunca arredonda 70 s para "1 min".
  def segundos(valor)
    return TRACO if valor.nil?

    total = valor.round
    return t('formato.segundos', n: numero(total)) if total < 60
    return t('formato.horas', n: decimal(total / 3600.0)) if total >= 3600

    minutos, resto = total.divmod(60)
    resto.zero? ? t('formato.minutos', n: numero(minutos)) : t('formato.minutos_e_segundos', m: numero(minutos), s: numero(resto))
  end

  # ['a', 'b', 'c'] → "a, b e c", com os conectores do próprio painel (o `to_sentence` puro cai no inglês).
  def lista(itens)
    Array(itens).compact.map(&:to_s).to_sentence(words_connector: t('formato.lista.virgula'),
                                                 two_words_connector: t('formato.lista.dois'),
                                                 last_word_connector: t('formato.lista.ultimo'))
  end

  # Base pequena demais para destacar uma taxa (igual a `poucosCasos` da tela): a taxa vira "poucos casos".
  def poucos_casos?(base)
    base.to_i < MINIMO_DA_TAXA
  end

  def dinheiro(valor, moeda = 'BRL')
    return TRACO if valor.nil?

    "#{MOEDAS.fetch(moeda.to_s, moeda.to_s)} #{decimal(valor, 0)}"
  end

  # Datas do contrato já vêm como texto no fuso da conta ('AAAA-MM-DD' ou 'AAAA-MM-DDTHH:mm').
  def dia_mes(data)
    "#{data.to_s[8, 2]}/#{data.to_s[5, 2]}"
  end

  def data_longa(data)
    "#{dia_mes(data)}/#{data.to_s[0, 4]}"
  end

  def dia_hora(data_hora)
    "#{dia_mes(data_hora)} #{data_hora.to_s[11, 5]}"
  end

  def periodo_texto(periodo)
    t('formato.periodo', inicio: dia_mes(periodo['inicio']), fim: data_longa(periodo['fim']))
  end

  # Nome de negócio pelo catálogo; id sem nome mostra "Sem nome", nunca o id cru.
  def nome_de(catalogo, tipo, id)
    valor = catalogo.to_h.dig(tipo.to_s, id.to_s)
    valor = valor['nome'] if valor.is_a?(Hash)
    valor.presence || t('sem_nome')
  end

  def nome_do_corte(catalogo, corte, valor)
    catalogo.to_h.dig('cortes', corte.to_s, valor.to_s).presence || t('sem_nome')
  end

  def prova_curta(prova)
    t('conversa', numero: prova['conversa'], quando: dia_hora(prova['quando']))
  end

  def dias_da_semana(dias)
    nomes = Array(dias).map { |dia| t('dias_curtos')[dia.to_i - 1] }
    consecutivos = dias.present? && dias.each_cons(2).all? { |a, b| b == a + 1 } && dias.size > 2
    consecutivos ? t('formato.intervalo', inicio: nomes.first, fim: nomes.last) : lista(nomes)
  end

  # O fuso como a plataforma mostra em Configurações da conta ("America/Sao Paulo"), igual a `rotuloDoFuso` do painel.
  # Nunca o nome longo ("Horário Padrão de ...").
  def fuso_legivel(fuso)
    fuso.to_s.tr('_', ' ')
  end

  # A frase de um aviso do painel (`avisos`), ou nil quando não há texto para ele.
  def texto_do_aviso(aviso)
    t("avisos.#{aviso['id']}", **valores_do_aviso(aviso), default: '').presence
  end

  def valores_do_aviso(aviso)
    valores = aviso['valores'].to_h.symbolize_keys
    valores[:dia] = data_longa(valores[:dia]) if valores[:dia]
    valores[:data] = data_longa(valores[:data]) if valores[:data]
    valores[:secoes] = lista(Array(valores[:secoes]).map { |secao| t("secoes.#{secao}") }) if valores.key?(:secoes)
    valores[:n] = numero(valores[:n]) if valores[:n]
    valores
  end

  # "fuso da sua conta (America/Sao Paulo)", a mesma frase da tela.
  def fuso_da_conta(fuso)
    t('formato.fuso_da_conta', fuso: fuso_legivel(fuso))
  end
end
