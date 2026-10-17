# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, aprovado pelo Rodrigo em 16/10/2026): o que o agente de
# IA não responde nem lê como atual, do que o recebimento da caixa WAHA grava.
# - Mensagem que o WhatsApp não deixa ler fora do celular (`is_unsupported`, a bolha "abra no celular"), na caixa WAHA
#   comum com a flag `whatsapp_rich_native`: se ela é a mensagem do turno, a IA fica calada (não há o que responder) e o
#   painel de Desempenho ganha o evento `skipped_mensagem_sem_suporte`, uma vez por mensagem. Noutra caixa, ou sem a
#   flag, como na main.
# - O aviso de visualização única que o aparelho vinculado não abre (`view_once_unavailable`), na mesma caixa e com a
#   flag: calada, com o mesmo evento da bolha "abra no celular", e fora do histórico.
# - Mensagem apagada pelo cliente (`deleted_by_contact_at`, gravada só pelo recebimento WAHA): se ela é a do turno, a IA
#   fica calada; e ela sai do histórico que vai à IA, para não ser lida como atual.
# Só depois da elegibilidade de sempre: turno que deixou de ser da IA segue o caminho original (sem evento).
module Waha::RichNative::AgentTurnGuard
  UNSUPPORTED_KEY = 'is_unsupported'.freeze
  DELETED_KEY = 'deleted_by_contact_at'.freeze
  VIEW_ONCE_KEY = Waha::RichNative::Inbound::ViewOnceUnavailable::KEY
  UNSUPPORTED_REASON = 'mensagem_sem_suporte'.freeze
  DELETED_REASON = 'apagada_pelo_cliente'.freeze

  def perform
    reason = c2y_turn_skip_reason
    return super if reason.nil? || !still_eligible?

    c2y_skip_turn!(reason)
  end

  private

  # O mesmo memo do original: a primeira chamada pega a janela dele e guarda já sem as apagadas.
  def recent_messages
    @recent_messages ||= super.reject { |message| c2y_out_of_history?(message) }
  end

  # Apagada pelo cliente, ou o aviso de visualização única (não há conteúdo para a IA ler).
  def c2y_out_of_history?(message)
    attributes = message.content_attributes.to_h
    attributes[DELETED_KEY].present? || attributes[VIEW_ONCE_KEY] == true
  end

  def c2y_turn_message
    return @c2y_turn_message if defined?(@c2y_turn_message)

    @c2y_turn_message = @reply_to_message_id.present? ? @conversation.messages.find_by(id: @reply_to_message_id) : nil
  end

  def c2y_turn_skip_reason
    turn = c2y_turn_message
    return if turn.nil?

    attributes = turn.content_attributes.to_h
    return DELETED_REASON if attributes[DELETED_KEY].present?

    UNSUPPORTED_REASON if (attributes[UNSUPPORTED_KEY] == true || attributes[VIEW_ONCE_KEY] == true) && c2y_waha_with_flag?(turn)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] c2y_turn_guard_failed conv=#{@conversation.id} #{e.class}")
    nil
  end

  def c2y_waha_with_flag?(message)
    Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(@conversation.account)
  end

  def c2y_skip_turn!(reason)
    soltar_posse
    registrar_silencio(reason)
    c2y_log_unsupported if reason == UNSUPPORTED_REASON
    self.class::Result.silenced
  end

  # Uma vez por mensagem do cliente (sem índice único: uma duplicata rara na corrida é aceita, como no #1669). O
  # EventLogger nunca levanta.
  def c2y_log_unsupported
    return if @agent.events.skipped_mensagem_sem_suporte.exists?(conversation_id: @conversation.id, message_id: c2y_turn_message.id)

    ::Autonomia::Agents::Operate::EventLogger.create!(agent: @agent, conversation: @conversation,
                                                      event_type: :skipped_mensagem_sem_suporte, message_id: c2y_turn_message.id,
                                                      handoff_reason: UNSUPPORTED_REASON)
  end
end
