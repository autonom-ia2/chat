# Como um caso da bateria (#1246) é descrito: as abas, as linhas e o gabarito.
#
# Gabarito de cada alvo (phone, email, name, company):
# - String: o cabeçalho certo; Array: qualquer um deles serve; Integer: a posição (planilha sem cabeçalho);
# - nil: o certo é "não tem essa coluna".
# pode_perguntar: alvos em que perguntar à pessoa é aceitável (há duas leituras honestas).
# decisao :auto: o motor deveria resolver sozinho; :perguntar: o certo é parar e pedir a escolha.
# alcance_por_linha: { número da linha na planilha => uma pessoa alcançaria quem está nela? }
BaseDeClientesEval::Aba = Struct.new(:nome, :linhas, :alcance, :cabecalho, :alcance_por_linha, keyword_init: true)

BaseDeClientesEval::Caso = Struct.new(:id, :titulo, :nivel, :formato, :opcoes, :abas, :aba_alvo, :alvos, :pode_perguntar, :decisao,
                                      :nota, keyword_init: true) do
  def cabecalho
    abas.fetch(aba_alvo).cabecalho
  end

  def alcance_humano
    abas.fetch(aba_alvo).alcance
  end

  def alcance_por_linha
    abas.fetch(aba_alvo).alcance_por_linha
  end
end

module BaseDeClientesEval::CasosDsl
  ALVOS = %i[phone email name company].freeze

  def casos
    @casos ||= []
  end

  # rubocop:disable Metrics/ParameterLists -- a ficha de um caso é uma lista plana
  def caso(id, titulo, nivel:, alvos:, formato: 'csv', opcoes: {}, aba_alvo: 0, decisao: :auto, pode_perguntar: [], nota: nil)
    abas = yield
    abas = [abas] unless abas.is_a?(Array) # Array(aba) desmontaria o Struct
    casos << BaseDeClientesEval::Caso.new(id: id, titulo: titulo, nivel: nivel, formato: formato, opcoes: opcoes, abas: abas,
                                          aba_alvo: aba_alvo, alvos: ALVOS.index_with { |alvo| alvos[alvo] },
                                          pode_perguntar: pode_perguntar, decisao: decisao, nota: nota)
  end

  # antes: linhas acima do cabeçalho (título, data, linha em branco); depois: rodapé.
  # O bloco devolve uma linha; células de contato são Dados::Celula, o resto é valor solto.
  def aba(cabecalhos, linhas, nome: 'Planilha1', antes: [], depois: [], sem_cabecalho: false, &)
    corpo = Array.new(linhas, &)
    topo = sem_cabecalho ? antes : [*antes, cabecalhos]
    alcance_por_linha = corpo.each_with_index.to_h { |linha, indice| [topo.size + indice + 1, alcancavel?(linha)] }
    BaseDeClientesEval::Aba.new(nome: nome, linhas: [*topo, *corpo.map { |linha| valores(linha) }, *depois],
                                alcance: alcance_por_linha.values.count(true), cabecalho: topo.size, alcance_por_linha: alcance_por_linha)
  end
  # rubocop:enable Metrics/ParameterLists

  def alcancavel?(linha)
    linha.any? { |celula| celula.is_a?(BaseDeClientesEval::Dados::Celula) && celula.alcanca }
  end

  def valores(linha)
    linha.map { |celula| celula.is_a?(BaseDeClientesEval::Dados::Celula) ? celula.valor : celula }
  end

  def vazio
    BaseDeClientesEval::Dados::Celula.new(valor: '', alcanca: false)
  end

  def lixo(texto)
    BaseDeClientesEval::Dados::Celula.new(valor: texto, alcanca: false)
  end
end
