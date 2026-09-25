# ESBOÇO DA FRENTE B (#681): só a assinatura combinada com a frente A, que traz o mapeamento neste mesmo caminho. Na
# junção das branches vale o arquivo da frente A.
module Autonomia::Prospecting::Scoring::WeightMapping
  module_function

  def from_legacy(_legacy_weights)
    raise NotImplementedError, 'Autonomia::Prospecting::Scoring::WeightMapping vem da frente A do #681'
  end
end
