# A aba Empresas da Lista nova de Relacionamentos (#2894): a página e o número de cada grupo. Vale o mesmo que a lista
# de empresas de hoje: Empresas ligado na conta (403 sem) e permissão de ver empresas.
class Api::V1::Accounts::Relacionamentos::EmpresasController < Api::V1::Accounts::Relacionamentos::BaseController
  self.registro_da_permissao = Company

  before_action :exigir_empresas

  def index
    @consulta = consulta
  end

  def contagens
    render json: consulta.contagens
  end

  private

  def exigir_empresas
    return if Current.account.feature_enabled?('companies')

    render json: { error: 'Companies are not enabled for this account' }, status: :forbidden
  end

  def consulta
    ::Relacionamentos::ConsultaDeEmpresas.new(Current.account, conferido(params.permit(:grupo, :busca, :ordem, :pagina)))
  end
end
