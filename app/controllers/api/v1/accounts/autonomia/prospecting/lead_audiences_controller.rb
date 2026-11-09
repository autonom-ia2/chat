# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): POST leads/audience { lead_ids, name } cria um
# Público de Campanhas com os leads escolhidos (AudienceFromLeads). Pede a prospecção (prospecting_manage, no
# BaseController) e gerenciar campanhas (campaign_manage), a mesma chave de criar Público em Campanhas. Sem os Públicos
# ligados (CAMPAIGN_JOURNEY_ENABLED e CAMPAIGN_IMPORT_ENABLED), 404 com a frase.
#
# GET leads/:id/audiences (#2775, F6): em quais listas da Prospecção a empresa está, para a gaveta ("Está na lista X ·
# Tirar"). O lead é o que a pessoa vê (leads_scope); sem contato, nenhuma lista.
class Api::V1::Accounts::Autonomia::Prospecting::LeadAudiencesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :ensure_audiences_enabled
  before_action :authorize_campaign_manage!

  def index
    lead = leads_scope.find(params[:id])
    lists = ::Autonomia::Prospecting::AudienceLists.new(Current.account)
    audiences = lists.containing(lead.contact_id).to_a
    locked = ::CampaignJourney::AudienceUsage.locked_ids(audiences)
    render json: { payload: audiences.map { |audience| { id: audience.id, name: audience.name, locked: locked.include?(audience.id) } } }
  end

  def create
    permitted = params.permit(:name, lead_ids: [])
    result = ::Autonomia::Prospecting::AudienceFromLeads.new(
      account: Current.account, user: Current.user, lead_ids: permitted[:lead_ids], name: permitted[:name].to_s,
      leads_scope: leads_scope
    ).perform
    render json: { payload: audience_payload(result) }, status: :created
  rescue ::Autonomia::Prospecting::AudienceFromLeads::Error => e
    render_audience_error(e)
  end

  private

  def audience_payload(result)
    {
      audience: { id: result.audience.id, name: result.audience.name, count: result.audience.valid_rows },
      entered_lead_ids: result.entered_lead_ids,
      left_out: result.left_out
    }
  end
end
