# O acesso por funil da pessoa logada (#1149, R16): as caixas em que ela tem acesso restrito. O painel usa para não
# oferecer "Participar da conversa" onde a API recusaria (#1148). Só leitura e só sobre a própria pessoa.
class Api::V1::Accounts::Crm::MeuAcessoController < Api::V1::Accounts::Crm::BaseController
  def show
    scope = ::Crm::Access::ConversationScope.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    render json: { payload: { restricted_inbox_ids: scope.restricted_inbox_ids } }
  end
end
