# ESBOÇO DA FRENTE B (#681): só a assinatura combinada com a frente A, que traz a fórmula do Orth neste mesmo caminho.
# Na junção das branches vale o arquivo da frente A. Até lá, calcular levanta NotImplementedError: no motor legado a
# busca segue sem a nota sombra (e registra o erro), e o motor do Orth não pode ser ligado.
class Autonomia::Prospecting::Scoring::OrthScorer
  Result = Struct.new(:score, :priority_score, :components, :negative_factors, :human_insight, :effective_weights, keyword_init: true)

  def initialize(leads:, mode:, weights:, filters:)
    @leads = leads
    @mode = mode
    @weights = weights
    @filters = filters
  end

  def perform
    raise NotImplementedError, 'Autonomia::Prospecting::Scoring::OrthScorer vem da frente A do #681'
  end
end
