# A gaveta "Metas do mês" de CRM › Números (#1991, F4 do #1871). Atrás da flag da conta (`crm_metas`, 404 desligada) e
# da Crm::MetasPolicy (administrador; no EE, `crm_metas_manage` com `crm_view`, ou `crm_admin`, sempre com `sales_value_view`).
#
#   GET metas   o mês de hoje (fuso da conta): os funis de Vender, a meta do funil e a de cada pessoa, com a sugestão
#   PUT metas   grava { mes, funis: [{ id, metaFunil, pessoas: [{ id, meta }] }] } (reais inteiros; vazio ou 0 tira a
#               meta; campo que não vem não muda)
#
# Funil ou pessoa fora do alcance de quem grava = 404 `crm.metas.fora_do_alcance`; valor que não é inteiro de 0 a
# 1 bilhão = 422 `crm.metas.valor_invalido`; a gaveta aberta num mês que já virou = 422 `crm.metas.mes_mudou`; duas
# gravações da mesma meta ao mesmo tempo = 409 `crm.metas.conflito`. Nada é gravado nesses casos.
class Api::V1::Accounts::Crm::MetasController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_metas_enabled
  before_action :authorize_metas

  rescue_from ::Crm::Metas::Salvar::Invalido do
    render_unprocessable('crm.metas.valor_invalido')
  end

  rescue_from ::Crm::Metas::Salvar::MesMudou do
    render_unprocessable('crm.metas.mes_mudou')
  end

  rescue_from ::Crm::Metas::Salvar::ForaDoAlcance do
    render json: { error: 'crm.metas.fora_do_alcance' }, status: :not_found
  end

  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: 'crm.metas.conflito' }, status: :conflict
  end

  def show
    render json: gaveta
  end

  def update
    ::Crm::Metas::Salvar.new(account: Current.account, user: Current.user, account_user: Current.account_user,
                             funis: metas_params[:funis], mes: metas_params[:mes]).perform
    render json: gaveta
  end

  private

  def gaveta
    ::Crm::Metas::Gaveta.new(account: Current.account, user: Current.user, account_user: Current.account_user).perform
  end

  def metas_params
    params.permit(:mes, funis: [:id, :metaFunil, { pessoas: %i[id meta] }])
  end

  def ensure_metas_enabled
    render json: { error: 'crm.metas.disabled' }, status: :not_found unless ::Crm::Config.metas_enabled?(Current.account)
  end

  def authorize_metas
    authorize :metas, :manage?, policy_class: ::Crm::MetasPolicy
  end
end
