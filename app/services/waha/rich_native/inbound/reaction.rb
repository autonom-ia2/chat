# `waha_reaction` (chat#1709, fase 3): a reação fica colada na mensagem reagida (Waha::RichNative::Reactions), e não
# vira bolha nova; a IA não responde a ela. A mensagem criada pelo conector vira atividade escondida apontando a
# reagida (`reaction_applied_to`), mesmo quando a reagida está noutra conversa do mesmo contato. `from_me`: reação feita
# no celular da empresa (a reação da EMPRESA, a mesma de quem reage pelo painel); senão, do contato.
# Sem a mensagem reagida (mandada pelo celular sem ligação, nota, apagada, falhada), a reação também vira atividade
# escondida (não aparece como bolha nem vira turno da IA), com o texto do conector guardado no `content` ("Reagiu com
# 👍"). O voto numa enquete desconhecida é diferente: é resposta real a uma enquete mandada pelo celular e continua
# visível (Waha::RichNative::Inbound::PollVote).
module Waha::RichNative::Inbound::Reaction
  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && Waha::RichNative::Reactions.valid_emoji?(data['emoji'].to_s)

    target = Waha::RichNative::Inbound.target_of(message)
    return hide_unmatched!(message) if target.nil?

    author = if data['from_me'] == true
               Waha::RichNative::Reactions.business_author
             else
               Waha::RichNative::Reactions.contact_author(message.conversation.contact_id)
             end
    Waha::RichNative::Reactions.apply!(target, emoji: data['emoji'].to_s, author: author, timestamp: data['timestamp'])
    Waha::RichNative::Inbound.hide!(message, 'reaction', 'reaction_applied_to' => target.id)
  end

  def hide_unmatched!(message)
    text = message.content
    Waha::RichNative::Inbound.hide!(message, 'reaction')
    message.content = text
  end
end
