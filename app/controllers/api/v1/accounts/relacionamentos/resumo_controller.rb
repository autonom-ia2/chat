# Os números da frase do topo da Lista nova de Relacionamentos (#2894). Os valores de compra (#3097), só para quem vê
# valor de venda.
class Api::V1::Accounts::Relacionamentos::ResumoController < Api::V1::Accounts::Relacionamentos::BaseController
  def show
    render json: ::Relacionamentos::Resumo.new(Current.account, com_valores: ::Crm::ValorDeVenda.ve?(Current.account_user)).call
  end
end
