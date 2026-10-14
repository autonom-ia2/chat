# Ouve `conversation.resolved` e enfileira a extração de FAQ (#284 · 2b). Mesmo mecanismo do
# Operate::MessageListener: registrado no AsyncDispatcher, decide o MÍNIMO barato aqui e delega ao
# job. Custo zero para quem não ligou: só enfileira se a caixa tem agente Autonom.ia COM a flag
# `faq_suggestions` — sem flag, nem job é criado.
class Autonomia::Agents::Faq::ConversationListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return if conversation&.id.blank?
    return unless Autonomia::Agents::Config.enabled?(conversation.account)

    # Quem respondia a conversa (#1433). Antes lia qualquer vínculo da caixa, inclusive o arquivado de um agente
    # excluído; agora só o ativo — com área na caixa, um find_by solto podia pegar a área no lugar da porta.
    agent_inbox = Autonomia::Agents::QuemResponde.agent_inbox(conversation)
    return unless agent_inbox&.agent&.faq_suggestions_enabled?

    Autonomia::Agents::Faq::SuggestJob.perform_later(conversation.id)
  end
end
