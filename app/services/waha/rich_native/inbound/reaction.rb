# `waha_reaction` (chat#1709, fase 3): a reação fica colada na mensagem reagida (Waha::RichNative::Reactions), e não
# vira bolha nova; a IA não responde a ela. A mensagem criada pelo conector vira atividade escondida apontando a
# reagida (`reaction_applied_to`). `from_me`: reação feita no celular da empresa (by 'phone'); senão, do contato.
# Sem a mensagem reagida (fora da conversa, ou antiga sem ligação), fica o texto comum, como antes.
module Waha::RichNative::Inbound::Reaction
  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && Waha::RichNative::Reactions.valid_emoji?(data['emoji'].to_s)

    target = Waha::RichNative::Inbound.target_of(message)
    return if target.nil?

    author = { 'by' => data['from_me'] == true ? 'phone' : 'contact' }
    Waha::RichNative::Reactions.apply!(target, emoji: data['emoji'].to_s, author: author)
    Waha::RichNative::Inbound.hide!(message, 'reaction_applied_to' => target.id)
  end
end
