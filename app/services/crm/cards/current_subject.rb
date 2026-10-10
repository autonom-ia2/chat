# Multifunil 7/11 (#1147): o card é o assunto atual de alguma conversa dele? A IA (etapa, campos, follow-up) só age no
# assunto atual: uma mensagem sobre um pedido não move o card do outro. Card sem conversa (criado à mão no Kanban) é
# sempre o próprio assunto.
module Crm::Cards::CurrentSubject
  module_function

  def card?(card)
    conversation_ids = ([card.conversation_id] + card.card_conversations.pluck(:conversation_id)).compact.uniq
    return true if conversation_ids.empty?

    finder = Crm::Cards::ConversationCardFinder.new(account: card.account)
    card.account.conversations.where(id: conversation_ids).any? { |conversation| finder.find(conversation)&.id == card.id }
  end
end
