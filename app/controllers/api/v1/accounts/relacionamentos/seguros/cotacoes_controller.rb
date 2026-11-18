# O consumo de cotações do mês no cartão de "Ajustar renovações" (E8, #2901, decisão D9): só leitura, com o mesmo que
# ler os ajustes pede (ver contatos). Só contagens (Carteira::Cotacao::Consumo). Sem a chave da cotação na conta, 422
# `cotacao_desligada`: a tela nem mostra o cartão.
class Api::V1::Accounts::Relacionamentos::Seguros::CotacoesController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros

  # GET seguros/cotacoes
  def show
    raise CustomExceptions::CarteiraRecusa, 'cotacao_desligada' unless ::Carteira::Cotacao::Liberada.para?(Current.account)

    render json: ::Carteira::Cotacao::Consumo.new(Current.account).call
  end
end
