# #1593 — "Passar para…" na conversa (Crm::PassarPara). GET: quem pode receber além das pessoas da caixa (agentes de
# IA, com a Fase 2 dos Agentes), com quem a conversa está e a origem da passagem. POST: passa para uma pessoa (a
# atribuição de hoje) ou um agente de IA. Recusa: 422 com `codigo`, que a tela diz em linguagem simples.
# Quem vê a conversa pode passá-la, como na atribuição (AssignmentsController). Só nas contas com a Fase 2 dos Agentes
# (o piloto): sem ela, a rota não existe para a conta (404), como o botão, que nem aparece.
# Robô (token de AgentBot, #1593): só o robô de outro sistema ligado à caixa da conversa (o n8n), e só para agente de
# IA. Espelho de agente nosso é recusado: agente da Autonomia nunca passa a conversa (#2154).
class Api::V1::Accounts::Conversations::PassarParaController < Api::V1::Accounts::Conversations::BaseController
  before_action :exigir_fase2
  before_action :exigir_robo_da_caixa, if: :robo?

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

  def robo?
    Current.user.is_a?(AgentBot)
  end

  # Ligado e ativo na caixa (AgentBotInbox), e não espelho de agente nosso.
  def exigir_robo_da_caixa
    ligado = @conversation.inbox.agent_bot_inbox
    return if ligado&.active? && ligado.agent_bot_id == Current.user.id && !espelho?(Current.user)

    render_unauthorized('Bot is not connected to this inbox')
  end

  def espelho?(robo)
    Autonomia::Agents::AgentInbox.espelhos.exists?(agent_bot_id: robo.id)
  end

  def servico
    Crm::PassarPara.new(conversation: @conversation.reload, usuario: Current.user)
  end

  def destino_params
    params.require(:destino).permit(:tipo, :id)
  end
end
