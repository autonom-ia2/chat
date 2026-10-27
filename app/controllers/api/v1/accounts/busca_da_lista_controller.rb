# #2211 — a busca dentro da lista de conversas: conversas (uma por pessoa), mensagens e pessoas sem conversa, num pedido
# só. A regra mora no SearchService (tipo 'Lista', SearchService::BuscaDaLista); aqui é só a porta. Lê só o `q`.
class Api::V1::Accounts::BuscaDaListaController < Api::V1::Accounts::BaseController
  def show
    @result = SearchService.new(
      current_user: Current.user,
      current_account: Current.account,
      search_type: SearchService::BuscaDaLista::TIPO,
      params: params.permit(:q)
    ).perform
  end
end
