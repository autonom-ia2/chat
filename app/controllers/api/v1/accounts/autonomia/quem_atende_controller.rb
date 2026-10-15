# chat#1648 — a aba "Agente externo" da caixa pergunta quais agentes da plataforma atendem ali, para travar a escolha.
# Fora da base dos Agentes (sem flag de módulo, de jornada ou de Fase 2): a recusa do set_agent_bot vale para todas as
# contas, e a tela precisa ler a mesma regra. Mesma autorização da tela de configuração da caixa (InboxPolicy#settings?).
class Api::V1::Accounts::Autonomia::QuemAtendeController < Api::V1::Accounts::BaseController
  def show
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :settings?

    render json: { agentes: ::Autonomia::Agents::QuemAtendeACaixa.agentes(inbox) }
  end
end
