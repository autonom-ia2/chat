# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): POST leads/audience { lead_ids, name } cria um
# Público de Campanhas com os leads escolhidos (AudienceFromLeads). Pede a prospecção (prospecting_manage, no
# BaseController) e gerenciar campanhas (campaign_manage), a mesma chave de criar Público em Campanhas. Sem os Públicos
# ligados (CAMPAIGN_JOURNEY_ENABLED e CAMPAIGN_IMPORT_ENABLED), 404 com a frase.
class Api::V1::Accounts::Autonomia::Prospecting::LeadAudiencesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :ensure_audiences_enabled
  before_action :authorize_campaign_manage!

  def create
    result = ::Autonomia::Prospecting::AudienceFromLeads.new(
      account: Current.account, user: Current.user, lead_ids: params.permit(lead_ids: [])[:lead_ids], name: params[:name].to_s,
      leads_scope: leads_scope
    ).perform
    render json: { payload: audience_payload(result) }, status: :created
  rescue ::Autonomia::Prospecting::AudienceFromLeads::Error => e
    render_audience_error(e)
  end

  private

  def ensure_audiences_enabled
    return if ::CampaignJourney::Config.enabled? && ::CampaignImports::Config.enabled?

    render json: { error: I18n.t('autonomia.prospecting.audience.errors.disabled'), code: 'prospecting.audience.disabled' },
           status: :not_found
  end

  def authorize_campaign_manage!
    render_campaign_forbidden unless campaign_manage?
  end

  def audience_payload(result)
    {
      audience: { id: result.audience.id, name: result.audience.name, count: result.audience.valid_rows },
      entered_lead_ids: result.entered_lead_ids,
      left_out: result.left_out
    }
  end

  # A frase do I18n em `error` (com o aviso de que os contatos criados ficaram, quando a recusa veio depois deles), o
  # código de máquina em `code` e quem ficou de fora e por quê.
  def render_audience_error(error)
    message = I18n.t("autonomia.prospecting.audience.errors.#{error.message}", max: ::Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS)
    message = "#{message} #{I18n.t('autonomia.prospecting.audience.errors.contacts_saved')}" if error.contacts_saved
    render json: { error: message, code: "prospecting.audience.#{error.message}", left_out: error.left_out }, status: :unprocessable_entity
  end
end
