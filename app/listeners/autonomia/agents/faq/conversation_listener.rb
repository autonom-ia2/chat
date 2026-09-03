# Ouve `conversation.resolved` e enfileira a extração de FAQ (#284 · 2b). Mesmo mecanismo do
# Operate::MessageListener: registrado no AsyncDispatcher, decide o MÍNIMO barato aqui e delega ao
# job. Custo zero para quem não ligou: só enfileira se a caixa tem agente Autonom.ia COM a flag
# `faq_suggestions` — sem flag, nem job é criado.
class Autonomia::Agents::Faq::ConversationListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return if conversation&.id.blank?
    return unless Autonomia::Agents::Config.enabled?(conversation.account)

    agent_inbox = Autonomia::Agents::AgentInbox.includes(:agent).find_by(inbox_id: conversation.inbox_id,
                                                                         account_id: conversation.account_id)
    return unless agent_inbox&.agent&.faq_suggestions_enabled?

    Autonomia::Agents::Faq::SuggestJob.perform_later(conversation.id)
  end
end
