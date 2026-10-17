# O rastro, no painel de Desempenho do agente de IA, da bolha "abra no celular" e do aviso de visualização única que a
# caixa WAHA comum recebeu com a flag `whatsapp_rich_native` (chat#1709, rodada de correção). Essas mensagens não são
# turno (Waha::RichNative::AgentListenerGuard): a IA não responde, e este job só grava `skipped_mensagem_sem_suporte` para
# o agente que atenderia a conversa, uma vez por mensagem. Conversa sem agente elegível (com pessoa responsável, agente
# desligado): nada.
class Waha::RichNative::UnsupportedTurnJob < ApplicationJob
  queue_as :medium
  EVENT_TYPE = :skipped_mensagem_sem_suporte

  def perform(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil? || !::Autonomia::Agents::Config.enabled?(conversation.account)

    agent = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)&.agent
    return if agent.nil? || agent.events.exists?(event_type: EVENT_TYPE, conversation_id: conversation.id, message_id: message_id)

    ::Autonomia::Agents::Operate::EventLogger.create!(agent: agent, conversation: conversation, event_type: EVENT_TYPE,
                                                      message_id: message_id,
                                                      handoff_reason: Waha::RichNative::AgentTurnGuard::UNSUPPORTED_REASON)
  end
end
