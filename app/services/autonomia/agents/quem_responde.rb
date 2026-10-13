# #1433 F1a — o PONTO ÚNICO que escolhe o vínculo (AgentInbox) que responde por uma conversa. Todo lugar que antes
# achava o agente pela caixa (`AgentInbox.kept.find_by(inbox_id:, account_id:)`) passa por aqui.
#
# - Chave da Fase 2 desligada (Autonomia::Agents::Fase2): a porta da caixa, como sempre foi. Antes do #1433 todo
#   vínculo era porta, então o resultado é o mesmo da consulta antiga.
# - Ligada: se o ai_assignee da conversa é o espelho de um vínculo ATIVO desta caixa (porta ou área), é esse vínculo;
#   senão, a porta. A área responde com o próprio espelho, então continua dona da conversa depois de responder
#   (Message#claim_conversation_for_bot) e a porta fica calada.
#
# Só ESCOLHE: o contrato de poder responder (agente ligado, conta, pessoa atribuída, allowlist) segue em
# Autonomia::Agents::Operate.authorized_agent_inbox / eligible_agent_inbox. Tenancy: só lê vínculo da conta da
# conversa.
module Autonomia::Agents::QuemResponde
  module_function

  def agent_inbox(conversation)
    return if conversation.blank?

    vinculos = ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    return vinculos.porta.take unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)

    dono_da_conversa(vinculos, conversation) || vinculos.porta.take
  end

  # A porta ativa da caixa, para quem ainda não tem a conversa (ex.: a reação do WhatsApp, antes de achar a conversa).
  def porta_da_caixa(inbox)
    return if inbox.blank?

    ::Autonomia::Agents::AgentInbox.kept.porta.find_by(inbox_id: inbox.id, account_id: inbox.account_id)
  end

  def dono_da_conversa(vinculos, conversation)
    return if conversation.assignee_agent_bot_id.blank? || conversation.ai_assignee_type != 'AgentBot'

    vinculos.find_by(agent_bot_id: conversation.assignee_agent_bot_id)
  end
  private_class_method :dono_da_conversa
end
