# Prepend em Autonomia::Agents::Operate::MessageListener (chat#1709, rodada de correção): na caixa WAHA comum com a flag
# `whatsapp_rich_native`, a bolha "abra no celular" (`is_unsupported`) e o aviso de visualização única
# (`view_once_unavailable`) NÃO são turno do cliente: não disparam o ReplyJob. Sem isto, o gatilho trocava a marca do
# debounce (`pending_message_id`) para a bolha, e a rajada [texto, bolha] era respondida a partir da bolha. Agora a
# rajada é respondida pelo texto, e a bolha sozinha não gera resposta.
# A IA continua deixando o rastro no painel de Desempenho (`skipped_mensagem_sem_suporte`, uma vez por mensagem), por
# um job à parte (Waha::RichNative::UnsupportedTurnJob), que só grava o evento. Sem a flag, ou noutra caixa: a main.
module Waha::RichNative::AgentListenerGuard
  def message_created(event)
    message = event.data[:message]
    return super unless c2y_not_a_turn?(message)
    return unless ::Autonomia::Agents::Config.enabled?(message.account)

    Waha::RichNative::UnsupportedTurnJob.perform_later(message.conversation_id, message.id)
  end

  private

  def c2y_not_a_turn?(message)
    message.present? && message.incoming? && !message.private? && message.conversation_id.present? &&
      Waha::RichNative::TurnKinds.kind(message) == :unsupported && Waha::RichNative::Inbound.waha_inbox?(message) &&
      Waha::RichNative.enabled?(message.account)
  end
end
