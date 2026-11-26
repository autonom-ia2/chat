# As FAIXAS DE IDADE de um plano do Seguro Viagem (#3211): toda busca de faixa passa por `faixa`, para o preço de cada
# viajante sair da mesma regra na cotação, no PDF e na proposta. O plano é o Hash de `Planos.de` (chaves em texto).
module Autonomia::Agents::Tools::Native::SeguroViagem::Faixas
  module_function

  # -> a faixa de `plano['faixas']` com `de <= idade <= ate`, ou nil (sem faixa, ou idade fora de
  # `idade_minima..idade_maxima`).
  def faixa(plano, idade)
    return nil if idade.nil? || !dentro_do_limite?(plano, idade)

    plano['faixas'].to_a.find { |faixa| idade.between?(faixa['de'].to_i, faixa['ate'].to_i) }
  end

  # -> o `'valor'` da faixa de cada idade, na ordem das idades (nil onde não há faixa).
  def precos_por_pessoa(plano, idades)
    idades.map { |idade| faixa(plano, idade)&.fetch('valor', nil) }
  end

  # A idade dentro de `idade_minima..idade_maxima` (sem limite, aceita). É a regra que `Planos` usa para tirar o plano
  # que não aceita algum viajante.
  def dentro_do_limite?(plano, idade)
    minima = plano['idade_minima']
    maxima = plano['idade_maxima']
    (minima.nil? || idade >= minima.to_i) && (maxima.nil? || idade <= maxima.to_i)
  end

  # A idade completa em `data` (a da saída da viagem): antes do aniversário naquele ano, um a menos.
  def idade_em(nascimento, data)
    antes_do_aniversario = ([data.month, data.day] <=> [nascimento.month, nascimento.day]).negative?
    data.year - nascimento.year - (antes_do_aniversario ? 1 : 0)
  end

  # A proposta só sai pelo preço cotado se as idades reais (pela data de nascimento) caem nas MESMAS faixas das idades
  # cotadas, em qualquer ordem: compara as contagens de cada faixa. Alguma idade sem faixa: false.
  def mesma_faixa?(plano, idades_cotadas, idades_reais)
    cotadas = idades_cotadas.map { |idade| faixa(plano, idade) }
    reais = idades_reais.map { |idade| faixa(plano, idade) }
    return false if cotadas.include?(nil) || reais.include?(nil)

    cotadas.tally == reais.tally
  end

  # As idades de cada viajante pela data de nascimento, na data de saída da cotação (ISO).
  def idades_na_saida(viajantes, saida)
    data = Date.iso8601(saida)
    viajantes.map { |pessoa| idade_em(pessoa['nascimento'], data) }
  end
end
