# chat#1626 — Prepend em Api::V1::Accounts::AgentBotsController (Configurações › Agentes externos).
# O AgentBot espelho de um agente da plataforma (autonomia_agent_inboxes.agent_bot_id) não é robô de fora: quem cria e
# apaga é o próprio Agentes IA (InboxConnector, Areas, SoftDelete), sem passar por esta API. Editar ou apagar um espelho
# por aqui derrubaria o agente na caixa. Então a API pública de robôs não o lista e responde 404 a ele, como se não
# existisse. Vale também para vínculo apagado logicamente: o espelho continua sendo o autor das mensagens antigas.
module Autonomia::Agents::RobosSemEspelho
  def index
    super
    @agent_bots = @agent_bots.where.not(id: espelhos_de_agentes)
  end

  private

  def agent_bot
    super
    raise ActiveRecord::RecordNotFound if Autonomia::Agents::AgentInbox.exists?(agent_bot_id: @agent_bot.id)

    @agent_bot
  end

  def espelhos_de_agentes
    Autonomia::Agents::AgentInbox.select(:agent_bot_id)
  end
end
