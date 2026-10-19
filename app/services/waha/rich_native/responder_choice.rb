# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, rodada de correção, item 15): o voto e a resposta ao
# convite chegam à IA com a pergunta. O `content` do turno é só a escolha ("Votou: Não"); no histórico, o item da
# escolha leva o texto completo (Waha::RichNative::AiChoiceText). Um caminho só: a pergunta do turno (`query`) fica a da
# main (o `content`), para o texto completo não entrar duas vezes no prompt. Com a moldura da equipe (#1669), o texto
# passa pela mesma neutralização do texto do cliente.
module Waha::RichNative::ResponderChoice
  private

  def history
    items = super
    messages = recent_messages
    return items unless items.is_a?(Array) && items.size == messages.size

    items.each_with_index.map { |item, index| with_choice_text(item, messages[index]) }
  end

  def with_choice_text(item, message)
    return item unless item.is_a?(Hash)

    choice = c2y_choice_text(message)
    choice ? item.merge(content: choice) : item
  end

  def c2y_choice_text(message)
    # O guard (Waha::RichNative::AgentTurnGuard) já decidiu, com o memo do turno, se a escolha vale.
    text = Waha::RichNative::AiChoiceText.for(message, current: !c2y_stale_choice?(message))
    return if text.nil?

    equipe.aplica? ? equipe.pergunta(text) : text
  rescue StandardError => e
    Waha::RichNative::SafeReport.capture(e, account: @conversation.account)
    Rails.logger.error("[waha] rich native choice text #{e.class}")
    nil
  end
end
