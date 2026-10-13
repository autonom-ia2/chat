# #1433 F1a — o agente da equipe numa caixa (vínculo de papel 'area').
#
# Chamado pela tela do CRM "Caixas no CRM → Quem cuida do quê?" (#1447) ao marcar/desmarcar o agente num funil da
# caixa. A área recebe a conversa quando alguém passa (pessoa ou outra IA, pela Atribuição do CRM: o espelho dela vira
# o ai_assignee) e responde com o PRÓPRIO espelho — Autonomia::Agents::QuemResponde escolhe quem responde.
#
# O espelho da área NÃO tem AgentBotInbox: assim inbox.agent_bot continua sendo a porta, e conversa nova continua
# nascendo com a porta (Conversation#set_active_bot_conversation).
#
# Os dois métodos são idempotentes e rodam em transação. Soltar arquiva o vínculo (deleted_at) e GUARDA o espelho:
# ele é o autor das mensagens que a área já mandou (destruir o AgentBot apagaria o autor delas). Vincular de novo
# reativa o mesmo vínculo e o mesmo espelho.
#
# Ponto de extensão (fora da F1a): a ferramenta passar_para_area, os limites e a assinatura do evento
# crm.ai.responsible_agent_changed entram depois, sobre estes dois métodos e o QuemResponde.
module Autonomia::Agents::Areas
  class AgenteInterno < StandardError; end

  module_function

  # -> o AgentInbox de área ativo. ActiveRecord::RecordInvalid quando a caixa não tem porta ativa, o agente já é a
  # porta dela, ou agente/caixa são de contas diferentes.
  def vincular!(agent:, inbox:)
    raise AgenteInterno, "agent #{agent.id} is internal and never talks to customers" if agent.actuation_internal?

    agent.with_lock do
      vinculos = ::Autonomia::Agents::AgentInbox.where(autonomia_agent_id: agent.id, inbox_id: inbox.id)
      vinculos.kept.area.first || reativar!(vinculos.area.order(deleted_at: :desc).first) || criar!(agent, inbox)
    end
  end

  # Solta o vínculo de área do agente na caixa (se houver) e devolve à porta as conversas que ele atendia.
  # Nunca toca a porta: soltar a porta é o InboxConnector.
  def desvincular!(agent:, inbox:)
    agent.with_lock do
      vinculo = ::Autonomia::Agents::AgentInbox.kept.area.find_by(autonomia_agent_id: agent.id, inbox_id: inbox.id)
      next if vinculo.nil?

      vinculo.release_bot_conversations!
      vinculo.update!(deleted_at: Time.current)
    end
  end

  def reativar!(vinculo)
    return if vinculo.nil?

    vinculo.update!(deleted_at: nil)
    vinculo
  end

  # Valida o vínculo antes de gravar o espelho: recusado, nenhum AgentBot fica para trás.
  def criar!(agent, inbox)
    espelho = AgentBot.new(account: agent.account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    ::Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: agent.account, agent_bot: espelho, papel: 'area')
  end
  private_class_method :reativar!, :criar!
end
