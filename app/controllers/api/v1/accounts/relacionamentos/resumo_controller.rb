# Os números da frase do topo da Lista nova de Relacionamentos (#2894).
class Api::V1::Accounts::Relacionamentos::ResumoController < Api::V1::Accounts::Relacionamentos::BaseController
  def show
    render json: ::Relacionamentos::Resumo.new(Current.account).call
  end
end
