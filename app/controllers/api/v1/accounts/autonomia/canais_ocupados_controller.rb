# #1181 (L2) — caixas da conta e quem atende cada uma: agente nativo (com nome) ou atendimento externo (sem nome).
class Api::V1::Accounts::Autonomia::CanaisOcupadosController < Api::V1::Accounts::Autonomia::JornadaBaseController
  def index
    render json: { payload: ::Autonomia::CanaisOcupadosFinder.new(account: Current.account, agents_scope: agents_scope).call }
  end
end
