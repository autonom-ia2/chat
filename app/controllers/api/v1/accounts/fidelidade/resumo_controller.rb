# Os números do painel da Fidelidade (#3100, Fidelidade::Resumo): clientes no cartão, perto do prêmio, cartões
# completos e prêmios dados em 30 dias. Sem cartão na conta: null.
class Api::V1::Accounts::Fidelidade::ResumoController < Api::V1::Accounts::Fidelidade::BaseController
  before_action -> { exigir(:view?) }

  def show
    render json: programa && ::Fidelidade::Resumo.new(programa).call
  end
end
