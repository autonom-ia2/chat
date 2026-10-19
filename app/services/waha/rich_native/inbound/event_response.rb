# `waha_event_response` (chat#1709, rodada 2): a resposta do cliente a um convite de evento nativo nosso (Vou / Não vou
# / Talvez), { event_message_id, response, extra_guests, response_id, timestamp } + in_reply_to (o evento). Fica
# agregada no evento (`event_responses`, Waha::RichNative::EventResponses) e a mensagem criada pelo conector vira
# atividade escondida, como o voto da enquete. O evento é conferido de novo (saída `event`, nativo, mesma conversa e
# caixa) e a resposta precisa ser uma das conhecidas. Sem isso, fica o texto comum ("Vou").
module Waha::RichNative::Inbound::EventResponse
  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash) && Waha::RichNative::EventResponses.valid_response?(data['response'])
    # Em grupo a resposta não é agregada (todos seriam a mesma pessoa): fica o texto do conector, visível.
    return if Waha::RichNative.group_conversation?(message.conversation)

    event = Waha::RichNative::EventResponses.event_for(data['event_message_id'], conversation_id: message.conversation_id,
                                                                                 inbox_id: message.inbox_id)
    return if event.nil?

    Waha::RichNative::EventResponses.record_response!(message, event, response: data['response'], extra_guests: data['extra_guests'],
                                                                      timestamp: data['timestamp'])
  end
end
