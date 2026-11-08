# O pedido em uma frase (#2696, F4): a IA da conta preenche "O quê?", "Onde?" e os ajustes, e a pessoa confere antes
# de buscar. Corpo: { frase }. Não busca nem grava nada. Pede prospecting_manage (POST), como criar a busca.
class Api::V1::Accounts::Autonomia::Prospecting::SearchInterpretationsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  def create
    payload = ::Autonomia::Prospecting::SearchInterpreter.new(account: Current.account, text: params.permit(:frase)[:frase]).perform
    render json: { payload: payload }
  rescue ::Autonomia::Prospecting::SearchInterpreter::Error => e
    render json: {
      error: I18n.t("autonomia.prospecting.interpret.errors.#{e.code}", max: ::Autonomia::Prospecting::SearchInterpreter::MAX_TEXT),
      code: "prospecting.interpret.#{e.code}"
    }, status: e.status
  end
end
