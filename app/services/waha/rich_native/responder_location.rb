# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, revisão da rodada 2): a localização do cliente que virou
# cartão de mapa (`content` nil) chega à IA como texto (Waha::RichNative::AiLocationText), no histórico e na pergunta
# do turno. Só mexe no item de mensagem que tenha a localização gravada (com legenda, a localização vem depois dela);
# qualquer outro fica igual. Com a
# moldura da equipe (#1669), o texto passa pela mesma neutralização do texto do cliente.
module Waha::RichNative::ResponderLocation
  private

  def history
    items = super
    messages = recent_messages
    return items unless items.is_a?(Array) && items.size == messages.size

    items.each_with_index.map { |item, index| with_location_text(item, messages[index]) }
  end

  def query
    text = super
    location = location_text_for(last_incoming_message)
    location ? [text.presence, location].compact.join("\n") : text
  end

  # A legenda do cliente (localização ao vivo com texto) fica, e a localização vem depois dela.
  def with_location_text(item, message)
    return item unless item.is_a?(Hash)

    location = location_text_for(message)
    location ? item.merge(content: [item[:content].to_s.strip.presence, location].compact.join("\n")) : item
  end

  def location_text_for(message)
    text = Waha::RichNative::AiLocationText.for(message)
    return if text.nil?

    equipe.aplica? ? equipe.pergunta(text) : text
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.error("[waha] rich native location text #{e.class}")
    nil
  end
end
