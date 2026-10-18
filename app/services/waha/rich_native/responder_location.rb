# Prepend em Autonomia::Agents::Operate::Responder (chat#1709): o que a IA lê de uma localização do cliente que virou
# cartão de mapa (Waha::RichNative::AiLocationText: só nome e endereço, sem coordenadas nem link) e de um cartão de
# contato, da equipe ou do cliente (Waha::RichNative::AiContactText, com o telefone), no histórico e na pergunta do
# turno. Só mexe no item da mensagem que traz um dos dois; com `content` (a legenda da localização ao vivo, o texto do
# conector), o resumo vem depois dele. Com a moldura da equipe (#1669), o texto passa pela mesma neutralização do texto
# do cliente. O formato é o do Autonomia::Agents::Operate::ResumoDaMensagemRica (#1753), regra única. Com a Fase 2
# (moldura da equipe), o histórico já sai do ResumoDaMensagemRica.texto: quando ele já resumiu a mensagem (devolveu
# outra coisa que o `content`), nada é somado, para o resumo não entrar duas vezes.
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
    return item if !item.is_a?(Hash) || resumida_pela_equipe?(message)

    location = location_text_for(message)
    location ? item.merge(content: [item[:content].to_s.strip.presence, location].compact.join("\n")) : item
  end

  # Com a Fase 2, o item é o ResumoDaMensagemRica.texto (PessoaDaEquipe): se ele não devolveu o próprio `content`, a
  # localização ou o contato já está no item.
  def resumida_pela_equipe?(message)
    equipe.aplica? && Autonomia::Agents::Operate::ResumoDaMensagemRica.texto(message) != message.content.to_s
  end

  # A localização (só nome e endereço) ou o cartão de contato (com o telefone) que a mensagem traz.
  def location_text_for(message)
    text = Waha::RichNative::AiLocationText.for(message) || Waha::RichNative::AiContactText.for(message)
    return if text.nil?

    equipe.aplica? ? equipe.pergunta(text) : text
  rescue StandardError => e
    Waha::RichNative::SafeReport.capture(e, account: @conversation.account)
    Rails.logger.error("[waha] rich native location text #{e.class}")
    nil
  end
end
