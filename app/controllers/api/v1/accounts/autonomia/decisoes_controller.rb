# A pessoa responde um caso do Decisor (#858). A resposta vira exemplo e, se o caso estava parado
# dentro do prazo e a resposta é a que segue, a automação retoma.
class Api::V1::Accounts::Autonomia::DecisoesController < Api::V1::Accounts::BaseController
  wrap_parameters false

  def resolver
    authorize(Autonomia::Decisor, :resolver?)
    decisao = Autonomia::DecisorDecisao.where(account_id: Current.account.id).find(params[:id])
    retomou = Autonomia::Decisores::Resolucao.new(decisao: decisao, user: Current.user).resolver!(params.require(:resposta).to_s)
    render json: { id: decisao.id, status: decisao.status, resposta: decisao.resposta, retomou: retomou }
  rescue Autonomia::Decisores::Resolucao::Recusada => e
    render_could_not_create_error(e.message)
  end
end
