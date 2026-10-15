# #1593 — "Passar para…" na conversa (Crm::PassarPara). GET: quem pode receber além das pessoas da caixa (agentes de
# IA, com a Fase 2 dos Agentes), com quem a conversa está e a origem da passagem. POST: passa para uma pessoa (a
# atribuição de hoje) ou um agente de IA. Recusa: 422 com `codigo`, que a tela diz em linguagem simples.
# Quem vê a conversa pode passá-la, como na atribuição (AssignmentsController). Só nas contas com a Fase 2 dos Agentes
# (o piloto): sem ela, a rota não existe para a conta (404), como o botão, que nem aparece.
class Api::V1::Accounts::Conversations::PassarParaController < Api::V1::Accounts::Conversations::BaseController
  before_action :exigir_fase2

  def show
    @retrato = servico.retrato
  end

  def create
    resultado = servico.passar!(tipo: destino_params[:tipo], id: destino_params[:id])
    return render(json: { codigo: resultado.codigo }, status: :unprocessable_entity) unless resultado.ok

    @assignee = resultado.assignee
    @retrato = servico.retrato
    render :show
  end

  private

  def exigir_fase2
    head :not_found unless Crm::AgentesIa.ligado?(Current.account)
  end

  def servico
    Crm::PassarPara.new(conversation: @conversation.reload, usuario: Current.user)
  end

  def destino_params
    params.require(:destino).permit(:tipo, :id)
  end
end
