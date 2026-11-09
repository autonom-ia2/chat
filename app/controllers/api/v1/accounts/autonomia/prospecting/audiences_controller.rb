# "Suas listas" da Prospecção nova (#2775, F6): as listas são os Públicos de Campanhas criados pela Prospecção
# (source 'prospecting'); o de outra origem ou de outra conta é 404. Pede a prospecção (prospecting_manage, no
# BaseController) e gerenciar campanhas (campaign_manage), a mesma chave do "Guardar lista" (LeadAudiencesController).
#
# - GET    audiences                 as listas, do mais novo ao mais velho, paginadas, com os números (AudienceLists);
# - GET    audiences/:id?page=       a lista com os números e uma página das empresas;
# - POST   audiences/:id/leads       { lead_ids } acrescenta leads (LeadsIntoAudience: mesmo teto e left_out do Guardar lista);
# - DELETE audiences/:id/members     { contact_ids } ou { lead_ids } tira da lista (a linha fica como removed);
# - POST   audiences/:id/members     { contact_ids } devolve quem foi tirado (o "Desfazer");
# - POST   audiences/:id/copy        cria uma cópia para editar (a lista já enviada não muda).
# Lista já usada em campanha que saiu: 422 audience_locked (CampaignJourney::AudienceUsage).
class Api::V1::Accounts::Autonomia::Prospecting::AudiencesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  DEFAULT_PER_PAGE = 25
  MAX_IDS = ::Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS

  before_action :ensure_audiences_enabled
  before_action :authorize_campaign_manage!
  before_action :fetch_audience, except: [:index]

  def index
    scope = lists.scope
    audiences = scope.offset((page - 1) * DEFAULT_PER_PAGE).limit(DEFAULT_PER_PAGE).to_a
    numbers = lists.numbers(audiences)
    total = scope.count
    render json: {
      payload: audiences.map { |audience| list_payload(audience, numbers[audience.id]) },
      meta: { page: page, per_page: DEFAULT_PER_PAGE, total_count: total, has_more: page * DEFAULT_PER_PAGE < total }
    }
  end

  def show
    members = lists.members(@audience, page: page, leads_scope: leads_scope)
    render json: {
      payload: list_payload(@audience, lists.numbers([@audience])[@audience.id]).merge(members: members[:members]),
      meta: { page: page, per_page: ::Autonomia::Prospecting::AudienceLists::MEMBERS_PER_PAGE, total_count: members[:total] }
    }
  end

  def add_leads
    result = ::Autonomia::Prospecting::LeadsIntoAudience.new(
      account: Current.account, user: Current.user, lead_ids: params.permit(lead_ids: [])[:lead_ids],
      leads_scope: leads_scope, audience: @audience
    ).perform
    render json: { payload: changed_payload(result.audience).merge(entered_lead_ids: result.entered_lead_ids, left_out: result.left_out) }
  rescue ::Autonomia::Prospecting::AudienceFromLeads::Error => e
    render_audience_error(e)
  end

  def remove_members
    contact_ids = member_contact_ids
    return render_list_error('no_members') if contact_ids.empty?

    result = ::CampaignJourney::AudienceMembership.remove(@audience, contact_ids)
    render json: { payload: changed_payload(result.audience).merge(removed_contact_ids: result.removed_contact_ids) }
  rescue ::CampaignJourney::AudienceMembership::Error => e
    render_list_error(e.message)
  end

  def restore_members
    contact_ids = permitted_contact_ids
    return render_list_error('no_members') if contact_ids.empty?

    result = list_changes.restore(@audience, contact_ids)
    render json: { payload: changed_payload(result.audience).merge(restored_contact_ids: result.added_contact_ids,
                                                                   skipped_contact_ids: result.skipped_contact_ids) }
  rescue ::CampaignJourney::AudienceMembership::Error => e
    render_list_error(e.message)
  end

  def copy
    result = list_changes.copy(@audience)
    render json: { payload: list_payload(result.audience, lists.numbers([result.audience])[result.audience.id])
      .merge(skipped_contact_ids: result.skipped_contact_ids) }, status: :created
  rescue ::CampaignJourney::AudienceWriter::Error => e
    render_list_error(e.message)
  end

  private

  def lists
    @lists ||= ::Autonomia::Prospecting::AudienceLists.new(Current.account)
  end

  def list_changes
    ::Autonomia::Prospecting::AudienceListChanges.new(account: Current.account, user: Current.user)
  end

  def fetch_audience
    @audience = lists.scope.find(params[:id])
  end

  def page
    @page ||= [params[:page].to_i, 1].max
  end

  def permitted_contact_ids
    ids_from(params.permit(contact_ids: [])[:contact_ids])
  end

  def permitted_lead_ids
    ids_from(params.permit(lead_ids: [])[:lead_ids])
  end

  # Ids inteiros e positivos, até o teto do pedido; o resto (texto, lista, negativo) não vale como id.
  def ids_from(values)
    Array(values).filter_map { |value| Integer(value.to_s, 10, exception: false) }.select(&:positive?).uniq.first(MAX_IDS)
  end

  # Tirar pelo contato (a aba "Suas listas") ou pelo lead (a gaveta): o lead só alcança o contato se quem pede o vê.
  def member_contact_ids
    contact_ids = permitted_contact_ids
    lead_ids = permitted_lead_ids
    contact_ids += leads_scope.where(id: lead_ids).where.not(contact_id: nil).pluck(:contact_id) if lead_ids.any?
    contact_ids.uniq
  end

  def list_payload(audience, numbers)
    { id: audience.id, name: audience.name, created_at: audience.created_at, **numbers }
  end

  def changed_payload(audience)
    { audience: list_payload(audience, lists.numbers([audience])[audience.id]) }
  end

  def render_list_error(code)
    render json: { error: I18n.t("autonomia.prospecting.audience.errors.#{code}"), code: "prospecting.audience.#{code}" },
           status: :unprocessable_entity
  end
end
