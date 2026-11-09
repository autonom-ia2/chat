# "Depois" da fila "Para chamar" da Prospecção nova (#2697, F5). POST leads/:id/queue_postponement tira a empresa da
# fila de quem pediu até o dia seguinte (no fuso da conta); DELETE é o "Desfazer". Vale por pessoa e fica no metadata
# do lead (ParaChamar), sem mexer em status, card ou contato. Pede a prospecção (prospecting_manage, no BaseController)
# e só alcança o lead que a pessoa vê (leads_scope): o de outra conta ou de fora da visibilidade é 404.
class Api::V1::Accounts::Autonomia::Prospecting::LeadQueuePostponementsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  def create
    lead = leads_scope.find(params[:id])
    day = queue.postpone!(lead)
    render json: { payload: { lead_id: lead.id, postponed_on: day.iso8601 } }
  end

  def destroy
    lead = leads_scope.find(params[:id])
    queue.resume!(lead)
    render json: { payload: { lead_id: lead.id, postponed_on: nil } }
  end

  private

  def queue
    ::Autonomia::Prospecting::ParaChamar.new(account: Current.account, user: Current.user)
  end
end
