# #1433 F1a — o PONTO ÚNICO que escolhe o vínculo (AgentInbox) que responde por uma conversa. Todo lugar que antes
# achava o agente pela caixa (`AgentInbox.kept.find_by(inbox_id:, account_id:)`) passa por aqui.
#
# - Chave da Fase 2 desligada (Autonomia::Agents::Fase2): a porta da caixa, como sempre foi. Antes do #1433 todo
#   vínculo era porta, então o resultado é o mesmo da consulta antiga.
# - Ligada: se o ai_assignee da conversa é o espelho de um vínculo ATIVO desta caixa (porta ou área), é esse vínculo;
#   senão, a porta. A área responde com o próprio espelho, então continua dona da conversa depois de responder
#   (Message#claim_conversation_for_bot) e a porta fica calada. Rede de segurança: dono que não pode falar com
#   cliente agora (pausado, interno, de sistema) não deixa a conversa muda — responde a porta.
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

  # #1606 ponto 3: a resposta pública de um robô não tira a conversa de OUTRO vínculo ativo da caixa que é o dono dela
  # (Message#claim_conversation_for_bot). Ex.: a porta postando atrasada enquanto a área atende. Só com a Fase 2; robô
  # que não é nosso (n8n) numa caixa sem vínculo nosso nunca é barrado. Chamar com a conversa travada.
  def dono_ativo_outro?(conversation, sender)
    return false unless sender.is_a?(AgentBot) && conversation.ai_assignee.is_a?(AgentBot)
    return false if conversation.ai_assignee == sender || !::Autonomia::Agents::Fase2.ligada?(conversation.account)

    vinculos = ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    return false if dono_da_conversa(vinculos, conversation).nil?

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:claim_barrado, conversation_id: conversation.id,
                                                                              dono: conversation.assignee_agent_bot_id, robo: sender.id)
    true
  end

  # #1673: o vínculo nosso que é dono da conversa e pode falar com o cliente agora (o espelho no nome é de um vínculo
  # ativo desta caixa, com o agente atendendo), ou nil. Só com a Fase 2. Espelho de vínculo arquivado, agente pausado
  # ou robô de fora (n8n): nil.
  def dono_ativo(conversation)
    return if conversation.blank? || !::Autonomia::Agents::Fase2.ligada?(conversation.account)

    vinculos = ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    dono_da_conversa(vinculos, conversation)
  end

  # Quem fica com a conversa depois da resposta pública do robô `sender`: ele, ou o dono que é outro vínculo ativo.
  def dono_depois_do_claim(conversation, sender)
    dono_ativo_outro?(conversation, sender) ? conversation.ai_assignee : sender
  end

  # #1606 ponto 4: para quem a conversa volta quando a pessoa sai dela (Conversations::AssignmentService). Com a Fase 2,
  # o espelho de área do responsável do funil do card em atendimento (leitor do CRM); sem ele, o robô da caixa (a
  # porta), como sempre foi. O robô do funil só vale se for o espelho de um vínculo ativo DESTA caixa, na conta da
  # conversa (fail-closed): espelho de outra caixa, de vínculo removido ou de outra conta é ignorado.
  def robo_da_devolucao(conversation)
    porta = conversation.inbox_agent_bot
    return porta unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)

    robo = ::Autonomia::Agents::ContratoDoFunil.robo_do_funil(conversation)
    robo = nil unless robo && espelho_na_caixa?(conversation, robo)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:devolucao, conversation_id: conversation.id,
                                                                          destino: robo ? :area : :porta)
    robo || porta
  end

  def espelho_na_caixa?(conversation, robo)
    ::Autonomia::Agents::AgentInbox.kept.exists?(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                                 agent_bot_id: robo.id)
  end
  private_class_method :espelho_na_caixa?

  def dono_da_conversa(vinculos, conversation)
    return if conversation.assignee_agent_bot_id.blank? || conversation.ai_assignee_type != 'AgentBot'

    dono = vinculos.includes(:agent).find_by(agent_bot_id: conversation.assignee_agent_bot_id)
    dono if dono&.agent&.atende_cliente?
  end
  private_class_method :dono_da_conversa
end
