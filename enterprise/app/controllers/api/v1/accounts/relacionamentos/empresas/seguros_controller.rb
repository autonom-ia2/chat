# Os seguros em que a empresa é o segurado (E4, #2897): o bloco Seguros da ficha da empresa, na ordem de urgência. Vale
# o mesmo que a ficha da empresa de hoje (Empresas ligado na conta, 403 sem; permissão de ver a empresa) e o que a
# carteira pede (ver contatos).
class Api::V1::Accounts::Relacionamentos::Empresas::SegurosController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :exigir_empresas
  before_action :sem_parametros

  def index
    empresa = Current.account.companies.find(params[:id])
    authorize empresa, :show?
    render json: apresentacao.por_urgencia(seguros_da_conta.where(company_id: empresa.id))
  end

  private

  # A mesma recusa da ficha da empresa (EmpresasController).
  def exigir_empresas
    return if Current.account.feature_enabled?('companies')

    render json: { error: 'Companies are not enabled for this account' }, status: :forbidden
  end
end
