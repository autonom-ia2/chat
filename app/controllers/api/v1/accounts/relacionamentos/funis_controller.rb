# Os funis com as etapas para o "Criar cards" da Lista nova de Relacionamentos (#2894), numa chamada só: os funis que a
# pessoa vê no quadro. Com o CRM desligado a lista vem vazia, e a tela diz que não há funil.
class Api::V1::Accounts::Relacionamentos::FunisController < Api::V1::Accounts::Relacionamentos::BaseController
  def index
    return render json: [] unless ::Crm::Config.enabled?

    authorize ::Crm::Pipeline, :index?
    render json: ::Relacionamentos::Funis.new(policy_scope(::Crm::Pipeline)).call
  end
end
