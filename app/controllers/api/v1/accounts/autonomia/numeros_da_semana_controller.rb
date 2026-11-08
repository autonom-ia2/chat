# #1181 (L1) — números da semana de cada agente numa chamada só (a lista não chama o Desempenho por cartão).
# `agent_id` opcional restringe a um agente da conta (a página do agente lê a mesma leitura).
# #2000: só as conversas que quem pede pode abrir, as mesmas da lista que o cartão abre.
class Api::V1::Accounts::Autonomia::NumerosDaSemanaController < Api::V1::Accounts::Autonomia::JornadaBaseController
  def index
    conversas = ::Autonomia::ContaDaIa.visiveis(user: Current.user, account: Current.account)
    finder = ::Autonomia::AgentesSemanaFinder.new(account: Current.account, agent_ids: agent_ids, conversas: conversas)
    render json: { range: finder.range, from: finder.from.iso8601, to: finder.to.iso8601, payload: finder.call }
  end

  private

  def agent_ids
    return [agents_scope.find(params[:agent_id]).id] if params[:agent_id].present?

    agents_scope.order(:id).pluck(:id)
  end
end
