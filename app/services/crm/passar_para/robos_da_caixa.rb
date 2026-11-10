# #2882 — os robôs de outro sistema (AgentBot, ex.: n8n) ligados à caixa, que o "Passar para…" oferece para devolver a
# conversa. É o mesmo robô que a atribuição de robô aceita (AgentBot.accessible_to, o filtro do AssignmentService),
# ativo na caixa (AgentBotInbox ativo).
#
# Fica de fora o espelho de um agente de IA nosso (o AgentBot de um vínculo em autonomia_agent_inboxes, inclusive de
# vínculo removido): o agente aparece pelo nome dele em "Agentes de IA", com as regras dos Agentes, e o espelho nunca é
# um robô de outro sistema.
#
#   Crm::PassarPara::RobosDaCaixa.de(conversation) -> [AgentBot] por nome
module Crm::PassarPara::RobosDaCaixa
  module_function

  def de(conversation)
    inbox_id = conversation.inbox_id
    ativos = AgentBotInbox.active.where(inbox_id: inbox_id).select(:agent_bot_id)
    espelhos = ::Autonomia::Agents::AgentInbox.where(inbox_id: inbox_id).select(:agent_bot_id)

    AgentBot.accessible_to(conversation.account).where(id: ativos).where.not(id: espelhos).order(:name, :id).to_a
  end
end
