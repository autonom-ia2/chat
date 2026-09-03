# Roda a extração de FAQ para UMA conversa resolvida (#284 · 2b). Todas as guardas caras vivem aqui:
# feature da conta, conversa ainda resolvida, agente Autonom.ia que a atendeu e a flag POR AGENTE
# (config['faq_suggestions'] == true — desligada por padrão: sem flag, nenhuma chamada de IA).
# Nunca levanta: uma falha aqui jamais afeta a resolução da conversa (já aconteceu, em outro processo).
class Autonomia::Agents::Faq::SuggestJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || !conversation.resolved?
    return unless Autonomia::Agents::Config.enabled?(conversation.account)

    agent = agent_for(conversation)
    return if agent.blank? || !agent.faq_suggestions_enabled?

    Autonomia::Agents::Faq::Extractor.new(agent: agent, conversation: conversation).call
  rescue StandardError => e
    Rails.logger.warn("[autonomia][faq] suggest_job_failed conv=#{conversation_id} #{e.class}")
    nil
  end

  private

  # O agente que ATENDEU a conversa (último evento replied/handoff dela); fallback: o agente ligado à
  # caixa hoje. Sem nenhum dos dois, a conversa não foi do agente → nada a extrair.
  def agent_for(conversation)
    event = Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id, account_id: conversation.account_id)
                                         .order(created_at: :desc).first
    return event.agent if event&.agent

    Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id, account_id: conversation.account_id)&.agent
  end
end
