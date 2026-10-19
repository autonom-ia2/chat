# Tela inicial da caixa de conversas (#1801): os números do resumo, só leitura, no escopo de quem pede.
class Api::V1::Accounts::TelaInicialController < Api::V1::Accounts::BaseController
  def resumo
    # Conta sem a tela não paga as contagens.
    return head :not_found unless Current.account.feature_enabled?('tela_inicial_resumo')

    render json: TelaInicial::Resumo.new(account: Current.account, user: Current.user, account_user: Current.account_user).perform
  end
end
