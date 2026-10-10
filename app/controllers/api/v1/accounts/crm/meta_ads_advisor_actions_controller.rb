# Os gestos da pessoa sobre cada ação do consultor de anúncios (#1110, F5). Só administrador (policy
# Crm::MetaAdsConnection :show?, a mesma da ação do dia).
#
# POST advisor_actions/:id/open    → primeiro clique no botão principal. Idempotente, não muda o status (D5.9).
# POST advisor_actions/:id/accept  → "Feito". Só de `open`; senão 422 not_open.
# POST advisor_actions/:id/dismiss → "Dispensar". Só de `open`; senão 422 not_open.
#
# Ação de outra conta, ou id que não existe: 404 not_found. `via` é `api` quando o pedido se autenticou pelo
# cabeçalho api_access_token, que é como o Guia chama (Autonomia::Guide::ChamadaInterna); a métrica de aceite
# conta só o painel (D5.11).
class Api::V1::Accounts::Crm::MetaAdsAdvisorActionsController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_administrator
  before_action :load_advisor_action

  def open
    @advisor_action.open!(Current.user, via: via)
    render_advisor_action
  end

  def accept
    @advisor_action.accept!(Current.user, via: via)
    render_advisor_action
  rescue ::Crm::MetaAdvisorAction::NotOpen
    render_unprocessable('not_open')
  end

  def dismiss
    @advisor_action.dismiss!(Current.user, via: via)
    render_advisor_action
  rescue ::Crm::MetaAdvisorAction::NotOpen
    render_unprocessable('not_open')
  end

  private

  def ensure_administrator
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).show?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def load_advisor_action
    @advisor_action = ::Crm::MetaAdvisorAction.where(account_id: Current.account.id).find_by(id: params[:id])
    render json: { error: 'not_found' }, status: :not_found if @advisor_action.nil?
  end

  def via
    authenticate_by_access_token? ? 'api' : 'panel'
  end

  def render_advisor_action
    render json: { advisor_action: @advisor_action.slice(:id, :status, :opened_at, :resolved_at) }
  end
end
