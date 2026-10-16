# `waha_reaction` (chat#1709, fase 3): a reação fica colada na mensagem reagida (Waha::RichNative::Reactions), e não
# vira bolha nova; a IA não responde a ela. A mensagem criada pelo conector vira atividade escondida apontando a
# reagida (`reaction_applied_to`), mesmo quando a reagida está noutra conversa do mesmo contato. `from_me`: reação feita
# no celular da empresa (a reação da EMPRESA, a mesma de quem reage pelo painel); senão, do contato.
# Sem a mensagem reagida (antiga sem ligação, nota, apagada, falhada), fica o texto comum, como antes.
module Waha::RichNative::Inbound::Reaction
  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && Waha::RichNative::Reactions.valid_emoji?(data['emoji'].to_s)

    target = Waha::RichNative::Inbound.target_of(message)
    return if target.nil?

    author = if data['from_me'] == true
               Waha::RichNative::Reactions.business_author
             else
               Waha::RichNative::Reactions.contact_author(message.conversation.contact_id)
             end
    Waha::RichNative::Reactions.apply!(target, emoji: data['emoji'].to_s, author: author, timestamp: data['timestamp'])
    Waha::RichNative::Inbound.hide!(message, 'reaction', 'reaction_applied_to' => target.id)
  end
end
