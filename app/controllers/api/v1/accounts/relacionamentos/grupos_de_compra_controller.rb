# #3097 — as faixas dos grupos de compra da conta (Relacionamentos::Compras::Faixas): quem vê a lista lê, para os nomes
# dos grupos ("Sem comprar há 3 a 6 meses"); só o administrador ajusta. Ajustar reagrupa a conta sem disparar automação.
# A resposta leva também se quem pede vê valor de venda (`ve_valores`): sem isso, a tela não oferece o filtro e as
# ordens por valor.
class Api::V1::Accounts::Relacionamentos::GruposDeCompraController < Api::V1::Accounts::Relacionamentos::BaseController
  before_action :sem_parametros, only: :show
  before_action :so_administrador, only: :update

  def show
    responder(::Relacionamentos::Compras::Faixas.da_conta(Current.account))
  end

  def update
    faixas = params.require(:faixas).permit(:campeao_compras, :campeao_dias, :em_risco_dias, :perdido_dias)
    responder(::Relacionamentos::Compras::Faixas.gravar(Current.account, faixas.to_h))
  end

  private

  def responder(faixas)
    render json: faixas.merge('ve_valores' => ::Crm::ValorDeVenda.ve?(Current.account_user))
  end

  def so_administrador
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
