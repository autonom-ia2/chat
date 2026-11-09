# "Suas listas" da Prospecção nova (#2775, F6): as listas são os Públicos de Campanhas criados pela Prospecção
# (source 'prospecting'); o de outra origem ou de outra conta é 404. Pede a prospecção (prospecting_manage, no
# BaseController) e gerenciar campanhas (campaign_manage), a mesma chave do "Guardar lista" (LeadAudiencesController).
#
# - GET    audiences?lead_ids[]=     as listas, do mais novo ao mais velho, com os números (AudienceLists), 25 por vez
#                                     por cursor (before_at e before_id, de meta.next_before_at/next_before_id: apagar
#                                     uma lista no meio não faz pular nenhuma); cursor inválido é 422 invalid_cursor;
#                                     com lead_ids, cada lista diz quais desses leads já estão nela (already_lead_ids),
#                                     para o "Pôr N empresas na lista" contar só quem entra;
# - GET    audiences/:id?after=      a lista com os números e uma página das empresas depois da linha `after` (cursor:
#                                     tirar alguém no meio não faz pular ninguém); meta.next_after é o próximo cursor;
# - POST   audiences/:id/leads       { lead_ids } acrescenta leads (LeadsIntoAudience: mesmo teto e left_out do Guardar lista);
# - DELETE audiences/:id/members     { contact_ids } ou { lead_ids } tira da lista (a linha fica como removed);
# - POST   audiences/:id/members     { contact_ids } devolve quem foi tirado (o "Desfazer");
# - POST   audiences/:id/copy        cria uma cópia para editar (a lista já enviada não muda).
# Lista já usada em campanha que saiu: 422 audience_locked (CampaignJourney::AudienceUsage). Mais de MAX_IDS ids em
# contact_ids ou lead_ids: 422 too_many_members (nada é cortado em silêncio).
class Api::V1::Accounts::Autonomia::Prospecting::AudiencesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  DEFAULT_PER_PAGE = 25
  MAX_IDS = ::Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS

  before_action :ensure_audiences_enabled
  before_action :authorize_campaign_manage!
  before_action :fetch_audience, except: [:index]

  def index
    return render_too_many if too_many?(raw_lead_ids)
    return render_list_error('invalid_cursor') if params[:before_at].present? && (before_at.nil? || before_id.nil?)

    result = lists.lists_page(before_at: before_at, before_id: before_id, per_page: DEFAULT_PER_PAGE)
    render json: { payload: index_payload(result[:audiences]), meta: index_meta(result[:next]) }
  end

  def show
    members = lists.members(@audience, after: params[:after], leads_scope: leads_scope)
    render json: {
      payload: list_payload(@audience, lists.numbers([@audience])[@audience.id]).merge(members: members[:members]),
      meta: { per_page: ::Autonomia::Prospecting::AudienceLists::MEMBERS_PER_PAGE, total_count: members[:total],
              next_after: members[:next_after], has_more: !members[:next_after].nil? }
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
    return render_too_many if too_many?(raw_contact_ids) || too_many?(raw_lead_ids)

    contact_ids = member_contact_ids
    return render_list_error('no_members') if contact_ids.empty?

    result = ::CampaignJourney::AudienceMembership.remove(@audience, contact_ids)
    render json: { payload: changed_payload(result.audience).merge(removed_contact_ids: result.removed_contact_ids) }
  rescue ::CampaignJourney::AudienceMembership::Error => e
    render_list_error(e.message)
  end

  def restore_members
    return render_too_many if too_many?(raw_contact_ids)

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

  # O cursor das listas (de meta.next_before_at e next_before_id); nil quando ausente ou inválido.
  def before_at
    @before_at ||= Time.iso8601(params[:before_at].to_s)
  rescue ArgumentError
    nil
  end

  def before_id
    id = Integer(params[:before_id].to_s, 10, exception: false)
    id if id&.positive?
  end

  def index_meta(next_cursor)
    { per_page: DEFAULT_PER_PAGE, total_count: lists.scope.count, has_more: !next_cursor.nil?,
      next_before_at: next_cursor&.dig(:before_at), next_before_id: next_cursor&.dig(:before_id) }
  end

  # Os ids como vieram no pedido, antes de filtrar: o teto conta estes, como o do Guardar lista (AudienceFromLeads).
  def raw_contact_ids
    Array(params.permit(contact_ids: [])[:contact_ids])
  end

  def raw_lead_ids
    Array(params.permit(lead_ids: [])[:lead_ids])
  end

  def permitted_contact_ids
    ids_from(raw_contact_ids)
  end

  def permitted_lead_ids
    ids_from(raw_lead_ids)
  end

  # Ids inteiros e positivos; o resto (texto, lista, negativo) não vale como id. O teto é conferido antes (too_many?).
  def ids_from(values)
    values.filter_map { |value| Integer(value.to_s, 10, exception: false) }.select(&:positive?).uniq
  end

  def too_many?(values)
    values.size > MAX_IDS
  end

  def render_too_many
    render json: { error: I18n.t('autonomia.prospecting.audience.errors.too_many_members', max: MAX_IDS),
                   code: 'prospecting.audience.too_many_members' }, status: :unprocessable_entity
  end

  # Tirar pelo contato (a aba "Suas listas") ou pelo lead (a gaveta): o lead só alcança o contato se quem pede o vê.
  def member_contact_ids
    contact_ids = permitted_contact_ids
    lead_ids = permitted_lead_ids
    contact_ids += leads_scope.where(id: lead_ids).where.not(contact_id: nil).pluck(:contact_id) if lead_ids.any?
    contact_ids.uniq
  end

  # Cada lista com os números e, dos lead_ids pedidos, os que já estão nela.
  def index_payload(audiences)
    numbers = lists.numbers(audiences)
    already = lists.lead_ids_in(audiences, permitted_lead_ids, leads_scope: leads_scope)
    audiences.map { |audience| list_payload(audience, numbers[audience.id]).merge(already_lead_ids: already[audience.id]) }
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
