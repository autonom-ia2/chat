# Compara a leitura do motor com o gabarito de um caso (#1246).
#
# Classes de cada alvo (celular, e-mail, nome, empresa):
# - certo: coluna certa, com confiança;
# - certo_perguntou: coluna certa sugerida, e perguntar era aceitável;
# - perguntou_a_toa: coluna certa, mas sem confiança onde não havia dúvida honesta;
# - sugestao_errada: coluna errada, sem confiança (a pessoa vê a sugestão errada e confirma ou corrige);
# - erro_silencioso: coluna errada COM confiança.
#
# Veredicto do caso, do pior para o melhor: critico (importaria errado sem perguntar) >
# sugestao_errada_confiante > sugestao_errada > parou_com_erro > perguntou_a_toa > perfeito.
class BaseDeClientesEval::Avaliacao
  ALVOS = %i[phone email name company].freeze

  # rodada: { motor: 'nova' | 'classica', leitura: ContactReading, repeticao:, segundos:, jev_bruto: (a resposta do Jev) }
  def initialize(caso, leitura, rodada)
    @caso = caso
    @leitura = leitura
    @rodada = rodada
    @jev_bruto = rodada[:jev_bruto]
  end

  def resultado
    base = { caso: @caso.id, titulo: @caso.titulo, nivel: @caso.nivel, motor: @rodada[:motor], repeticao: @rodada[:repeticao],
             segundos: @rodada[:segundos]&.round(2), alcance_humano: @caso.alcance_humano }
    return base.merge(veredicto: 'parou_com_erro', erro: @leitura.message) if @leitura.is_a?(Exception)

    alvos = ALVOS.index_with { |alvo| alvo_resultado(alvo) }
    base.merge(cabecalho_ok: cabecalho_ok?, perguntou: perguntou?, jev: jev_resumo, alvos: alvos, linhas: linhas,
               veredicto: veredicto(alvos))
  end

  private

  def resolucao
    @leitura.resolution
  end

  def perguntou?
    resolucao['needs_confirmation']
  end

  # Planilha sem cabeçalho não tem linha certa: só conta se o motor parou para perguntar.
  def cabecalho_ok?
    return nil if @caso.cabecalho.zero?

    resolucao['header_row'] == @caso.cabecalho && resolucao['table_index'] == @caso.aba_alvo
  end

  def jev_resumo
    jev = resolucao['jev'].to_h
    escolhas = @jev_bruto&.dig(:targets)&.transform_values do |resposta|
      [resposta[:index] && @leitura.headers[resposta[:index]], resposta[:confidence]]
    end
    { status: jev['status'], schema_probability: jev['schema_probability'], erro: jev['error'], escolhas: escolhas }.compact
  end

  def alvo_resultado(alvo)
    entrada = resolucao.dig('targets', alvo.to_s).to_h
    coluna = entrada['column']
    certo = aceitaveis(alvo).any? { |esperado| bate?(esperado, coluna) } && cabecalho_ok? != false
    { esperado: @caso.alvos[alvo], obtido: entrada['header'], coluna: coluna, confiante: entrada['confident'],
      confianca: entrada['confidence'], fonte: entrada['source'], classe: classe(alvo, certo, entrada['confident']) }
  end

  def aceitaveis(alvo)
    esperado = @caso.alvos[alvo]
    esperado.is_a?(Array) ? esperado : [esperado]
  end

  def bate?(esperado, coluna)
    return coluna.nil? if esperado.nil?
    return coluna == esperado if esperado.is_a?(Integer)

    !coluna.nil? && @leitura.headers[coluna] == esperado
  end

  def classe(alvo, certo, confiante)
    return confiante ? 'certo' : pergunta(alvo) if certo

    confiante ? 'erro_silencioso' : 'sugestao_errada'
  end

  def pergunta(alvo)
    @caso.pode_perguntar.include?(alvo) || @caso.decisao == :perguntar ? 'certo_perguntou' : 'perguntou_a_toa'
  end

  def veredicto(alvos)
    classes = alvos.values.pluck(:classe)
    return erro_confiante if classes.include?('erro_silencioso') || cabecalho_ok? == false
    return 'critico' if @caso.decisao == :perguntar && !perguntou?

    %w[sugestao_errada perguntou_a_toa].find { |classe| classes.include?(classe) } || 'perfeito'
  end

  # Coluna errada com confiança: se o motor parou para perguntar, a pessoa ainda vê a sugestão errada.
  def erro_confiante
    perguntou? ? 'sugestao_errada_confiante' : 'critico'
  end

  # Linha a linha, contra o gabarito: perdidas são as que uma pessoa alcançaria e o motor não;
  # inventadas, as que o motor aceita sem ninguém alcançável nela (um número do exterior lido como +55).
  # Repetidas contam aqui; o validador fica com a primeira.
  def linhas
    telefone, email = @leitura.mapping.values_at('phone', 'email')
    aceitas = @leitura.rows.select { |linha| alcanca?(linha, telefone, email) }
    acertos = aceitas.count { |linha| humano?(linha) }
    chaves = aceitas.map { |linha| chave(linha, telefone, email) }
    { total: @leitura.rows.size, validas: aceitas.size, repetidas: chaves.size - chaves.uniq.size,
      perdidas: @caso.alcance_humano - acertos, inventadas: aceitas.size - acertos }
  end

  def humano?(linha)
    @caso.alcance_por_linha.fetch(linha.row_number, false)
  end

  def leitura_de_contato
    @rodada.fetch(:leitura)
  end

  def alcanca?(linha, telefone, email)
    leitura_de_contato.phone?(valor(linha, telefone)) || leitura_de_contato.email?(valor(linha, email))
  end

  def chave(linha, telefone, email)
    numero = valor(linha, telefone)
    return valor(linha, email).strip.downcase unless leitura_de_contato.phone?(numero)

    leitura_de_contato.phone(numero).phone_number
  end

  def valor(linha, indice)
    indice.nil? ? '' : linha.values[indice].to_s
  end
end
