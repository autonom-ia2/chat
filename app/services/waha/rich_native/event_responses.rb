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

  # timestamp: a hora da resposta no WhatsApp (`timestampMs`, Waha::RichNative::EventTime). A resposta guardada da mesma
  # pessoa só é substituída por uma igual ou mais nova: um job refeito com a resposta antiga não troca a atual.
  # Devolve :changed (resposta nova de fato: primeira, diferente, ou hora do motor estritamente mais nova), :same
  # (a mesma resposta refeita) ou nil (antiga, nada gravado). Só :changed vira turno do cliente para a IA.
  def apply!(event, sender:, response:, extra_guests: 0, timestamp: nil)
    at = Waha::RichNative::EventTime.iso8601(timestamp)
    result = nil
    event.with_lock do
      current = Array(event.content_attributes.to_h[KEY])
      previous = current.find { |entry| same_person?(entry, sender) }
      next if previous && !Waha::RichNative::EventTime.replaces?(at, previous['at'])

      result = changed?(previous, response, extra_guests, timestamp) ? :changed : :same
      store!(event, current, sender, { 'response' => response, 'extra_guests' => extra_guests.to_i, 'at' => at })
    end
    result
  end

  def store!(event, current, sender, fields)
    responses = current.reject { |entry| same_person?(entry, sender) }
    responses << { 'sender_type' => sender.class.name, 'sender_id' => sender.id }.merge(fields)
    event.content_attributes = event.content_attributes.to_h.merge(KEY => responses)
    event.save!(validate: false)
  end

  def changed?(previous, response, extra_guests, timestamp)
    previous.nil? || previous['response'] != response || previous['extra_guests'].to_i != extra_guests.to_i ||
      Waha::RichNative::EventTime.newer?(timestamp, previous['at'])
  end

  # A resposta desta pessoa ainda guardada no evento é `response`? (Conferido no settle, Waha::RichNative::AgentTurnGuard.)
  def current?(event, sender_type:, sender_id:, response:)
    entry = Array(event.content_attributes.to_h[KEY]).find do |item|
      item.is_a?(Hash) && item['sender_type'] == sender_type && item['sender_id'] == sender_id
    end
    entry.present? && entry['response'] == response
  end

  def same_person?(entry, sender)
    entry.is_a?(Hash) && entry['sender_type'] == sender.class.name && entry['sender_id'] == sender.id
  end

  # Grava a resposta no evento. A mensagem da resposta (ainda não gravada) vira o turno do cliente para a IA quando a
  # resposta é nova (Waha::RichNative::AiTurn); uma antiga (job refeito) vira atividade escondida.
  def record_response!(message, event, response:, extra_guests: 0, timestamp: nil)
    applied = apply!(event, sender: event.conversation.contact, response: response, extra_guests: extra_guests, timestamp: timestamp)
    return Waha::RichNative::Inbound.hide!(message, HIDDEN_KIND, APPLIED_KEY => event.id) unless applied == :changed

    extra = { APPLIED_KEY => event.id }.merge(Waha::RichNative::AiTurn.choice('event_response', event, response))
    Waha::RichNative::AiTurn.record!(message, Waha::RichNative::AiTurn.event_text(event.account, event, response), extra)
  end
end
