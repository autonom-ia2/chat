# `waha_edit` (chat#1709, fase 3): a mensagem editada no WhatsApp substitui o texto da original
# (Waha::RichNative::Edits, com o anterior guardado em `edit_history`), e não vira bolha nova; a IA não responde de
# novo. A original precisa ter o mesmo sentido: do cliente (incoming) quando `from_me` é falso; nossa (outgoing) quando é
# verdadeiro (editada no celular da empresa). A mensagem criada pelo conector vira atividade escondida
# (`edit_applied_to`). Sem a original (nota, apagada, falhada, de outro contato) ou com texto acima do teto do
# WhatsApp, fica o texto comum, como antes. Edição que chega fora de ordem (o `timestamp` do conector c2y-rich-5 mais
# velho que a última edição guardada) não troca o texto: fica só a atividade escondida.
module Waha::RichNative::Inbound::Edit
  module_function

  def apply(message, data)
    return unless text?(data)

    from_me = data['from_me'] == true
    target = Waha::RichNative::Inbound.target_of(message, message_type: from_me ? :outgoing : :incoming)
    return if target.nil?

    author = from_me ? Waha::RichNative::Edits.user_author : Waha::RichNative::Edits.contact_author(message.conversation.contact_id)
    Waha::RichNative::Edits.apply!(target, content: data['text'], author: author, timestamp: data['timestamp'])
    Waha::RichNative::Inbound.hide!(message, 'edit', 'edit_applied_to' => target.id)
  end

  def text?(data)
    data.is_a?(Hash) && Waha::RichNative::Edits.valid_text?(data['text'])
  end
end
