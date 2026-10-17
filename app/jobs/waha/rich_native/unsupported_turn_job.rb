# O rastro, no painel de Desempenho do agente de IA, da bolha "abra no celular" e do aviso de visualização única que a
# caixa WAHA comum recebeu com a flag `whatsapp_rich_native` (chat#1709, rodada de correção). Essas mensagens não são
# turno (Waha::RichNative::AgentListenerGuard): a IA não responde a elas. O evento `skipped_mensagem_sem_suporte` diz
# que a IA ficou CALADA, então só é gravado quando o turno inteiro em volta da mensagem é calado, pela mesma regra do
# settle (Waha::RichNative::TurnKinds.silent_reason): numa rajada [texto, bolha], a IA respondeu ao texto e não houve
# silêncio. Por isso o job espera o debounce do agente (as mensagens que chegam nele entram no mesmo turno) antes de
# conferir. Uma vez por mensagem; conversa sem agente elegível (com pessoa responsável, agente desligado): nada.
class Waha::RichNative::UnsupportedTurnJob < ApplicationJob
  queue_as :medium
  EVENT_TYPE = :skipped_mensagem_sem_suporte

  def perform(conversation_id, message_id, phase = 'trigger')
    message = Message.find_by(id: message_id, conversation_id: conversation_id)
    agent = message && agent_for(message.conversation)
    return if agent.nil?
    return wait_for_the_turn(agent, conversation_id, message_id) unless phase == 'settle'

    record!(agent, message.conversation, message) if silent_turn?(message.conversation, message)
  end

  private

  def agent_for(conversation)
    return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

    ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)&.agent
  end

  def wait_for_the_turn(agent, conversation_id, message_id)
    self.class.set(wait: ::Autonomia::Agents::Config.debounce_seconds_for(agent)).perform_later(conversation_id, message_id, 'settle')
  end

  # As mensagens do cliente entre a última resposta (nossa, de pessoa ou robô) antes da bolha e a primeira depois dela.
  def silent_turn?(conversation, message)
    chat = conversation.messages.where(private: false).where.not(message_type: :activity).reorder(:id)
    replies = chat.where.not(message_type: :incoming)
    before = replies.where(id: ...message.id).last
    after = replies.where('id > ?', message.id).first
    turn = chat.incoming.where('id > ?', before&.id.to_i)
    turn = turn.where(id: ...after.id) if after
    Waha::RichNative::TurnKinds.silent_reason(turn.to_a).present?
  end

  def record!(agent, conversation, message)
    return if agent.events.exists?(event_type: EVENT_TYPE, conversation_id: conversation.id, message_id: message.id)

    ::Autonomia::Agents::Operate::EventLogger.create!(agent: agent, conversation: conversation, event_type: EVENT_TYPE,
                                                      message_id: message.id,
                                                      handoff_reason: Waha::RichNative::AgentTurnGuard::UNSUPPORTED_REASON)
  end
end
