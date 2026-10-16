# `waha_edit` (chat#1709, fase 3): a mensagem editada no WhatsApp substitui o texto da original
# (Waha::RichNative::Edits, com o anterior guardado em `edit_history`), e não vira bolha nova; a IA não responde de
# novo. A original precisa ter o mesmo sentido: do cliente (incoming) quando `from_me` é falso; nossa (outgoing) quando é
# verdadeiro (editada no celular da empresa). A mensagem criada pelo conector vira atividade escondida
# (`edit_applied_to`). Sem a original (ou com ela apagada), fica o texto comum, como antes.
module Waha::RichNative::Inbound::Edit
  module_function

  def apply(message, data)
    return unless text?(data)

    from_me = data['from_me'] == true
    target = Waha::RichNative::Inbound.target_of(message, message_type: from_me ? :outgoing : :incoming)
    return if target.nil? || target.content_attributes.to_h['deleted']

    Waha::RichNative::Edits.apply!(target, content: data['text'], author: { 'by' => from_me ? 'phone' : 'contact' })
    Waha::RichNative::Inbound.hide!(message, 'edit_applied_to' => target.id)
  end

  def text?(data)
    data.is_a?(Hash) && data['text'].is_a?(String) && data['text'].strip.present?
  end
end
