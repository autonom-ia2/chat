# "Não quer ser contatado" no painel do lead (chat#713, decisão de 26/09). A recusa da pessoa fica no lead
# (consent_refused_at), sem mudar o status, e vai para os contatos que ela alcança pelo ContactOptOutSync. As rotas ficam
# em leads/:id/consent_refusal (POST marca, DELETE desfaz) e pedem a prospecção (prospecting_manage); o lead vem do que a
# pessoa vê (leads_scope, #732). Devolvem o lead como GET leads/:id devolve para essa pessoa.
class Api::V1::Accounts::Autonomia::Prospecting::LeadConsentRefusalsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  # Grava com quem marcou e tira o lead do segmento no job da Prospecção. Lead que já recusou fica como está.
  def create
    lead = leads_scope.find(params[:id])
    consent_sync.refuse!(lead, user: Current.user)
    ::Autonomia::Prospecting::SegmentRefusalSync.enqueue(account: Current.account, leads: [lead])

    render_lead(lead)
  end

  # "Desfazer: pode ser contatado": tira a recusa do lead e a marca da Prospecção que nenhuma outra recusa sustenta.
  def destroy
    lead = leads_scope.find(params[:id])
    consent_sync.withdraw!(lead)

    render_lead(lead)
  end

  private

  def consent_sync
    ::Autonomia::Prospecting::ContactOptOutSync.new(account: Current.account)
  end

  def render_lead(lead)
    render json: { payload: visible_lead_payload(lead_payload_builder.build(lead.reload)) }
  end
end
