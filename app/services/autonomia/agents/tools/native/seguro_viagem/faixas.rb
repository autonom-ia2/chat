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

  def dentro_do_limite?(plano, idade)
    minima = plano['idade_minima']
    maxima = plano['idade_maxima']
    (minima.nil? || idade >= minima.to_i) && (maxima.nil? || idade <= maxima.to_i)
  end

  private_class_method :dentro_do_limite?
end
