# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, revisão da rodada 2): a localização do cliente que virou
# cartão de mapa (`content` nil) chega à IA como texto (Waha::RichNative::AiLocationText), no histórico e na pergunta
# do turno. Só preenche o item de mensagem SEM texto que tenha a localização gravada; qualquer outro fica igual. Com a
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

  def with_location_text(item, message)
    return item unless item.is_a?(Hash) && item[:content].to_s.strip.empty?

    location = location_text_for(message)
    location ? item.merge(content: location) : item
  end

  def location_text_for(message)
    text = Waha::RichNative::AiLocationText.for(message)
    return if text.nil?

    equipe.aplica? ? equipe.pergunta(text) : text
  rescue StandardError => e
    Rails.logger.error("[waha] rich native location text #{e.class}")
    nil
  end
end
