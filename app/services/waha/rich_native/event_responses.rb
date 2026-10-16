# As respostas a um convite de evento nativo nosso (chat#1709, rodada 2), AGREGADAS na mensagem do evento, como os
# votos da enquete (Waha::RichNative::PollVotes):
#   content_attributes.event_responses = [{ "sender_type" => "Contact", "sender_id" => 12, "response" => "going",
#                                           "extra_guests" => 0, "at" => ISO 8601 }]
# Uma por pessoa: a nova substitui a anterior. response: going | not_going | maybe. Comum à caixa WAHA comum
# (Waha::RichNative::Inbound::EventResponse) e ao plano B do Híbrido (WhatsappHybrid::RichNative::EventResponseJob). O
# evento precisa ser NOSSO: mensagem de saída `event` que saiu nativa, na mesma conversa e caixa. A mensagem da
# resposta vira atividade escondida (`event_response_applied_to`). Grava sob trava e sem as validações do modelo; o
# `message_updated` leva a mudança à tela e não vai ao conector (Waha::RichNative::SilentUpdate).
module Waha::RichNative::EventResponses
  KEY = 'event_responses'.freeze
  TYPE = 'event'.freeze
  RESPONSES = %w[going not_going maybe].freeze
  HIDDEN_KIND = 'event_response'.freeze
  APPLIED_KEY = 'event_response_applied_to'.freeze

  module_function

  def event_for(message_id, conversation_id:, inbox_id:)
    event = Message.find_by(id: message_id, conversation_id: conversation_id, inbox_id: inbox_id, message_type: :outgoing)
    event if native_event?(event)
  end

  def native_event?(message)
    return false if message.nil?

    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == TYPE && Waha::RichNative.sent_native?(message)
  end

  def valid_response?(response)
    RESPONSES.include?(response)
  end

  def apply!(event, sender:, response:, extra_guests: 0)
    event.with_lock do
      responses = Array(event.content_attributes.to_h[KEY]).reject do |entry|
        entry.is_a?(Hash) && entry['sender_type'] == sender.class.name && entry['sender_id'] == sender.id
      end
      responses << { 'sender_type' => sender.class.name, 'sender_id' => sender.id, 'response' => response,
                     'extra_guests' => extra_guests.to_i, 'at' => Time.current.iso8601 }
      event.content_attributes = event.content_attributes.to_h.merge(KEY => responses)
      event.save!(validate: false)
    end
  end

  # Grava a resposta no evento e transforma a mensagem da resposta (ainda não gravada) em atividade escondida.
  def record_response!(message, event, response:, extra_guests: 0)
    apply!(event, sender: event.conversation.contact, response: response, extra_guests: extra_guests)
    Waha::RichNative::Inbound.hide!(message, HIDDEN_KIND, APPLIED_KEY => event.id)
  end
end
