# Multifunil 7/11 (#1147): o card é o assunto atual de alguma conversa dele? A IA (etapa, campos, follow-up) só age no
# assunto atual: uma mensagem sobre um pedido não move o card do outro. Card sem conversa (criado à mão no Kanban) é
# sempre o próprio assunto.
module Crm::Cards::CurrentSubject
  module_function

  def card?(card)
    conversation_ids = ([card.conversation_id] + card.card_conversations.pluck(:conversation_id)).compact.uniq
    return true if conversation_ids.empty?

    # Uma consulta para todas as conversas, na ordem do assunto atual: o primeiro card de cada conversa é o atual.
    rows = Crm::Cards::ConversationCardFinder.new(account: card.account).all_for(conversation_ids)
    rows.group_by(&:listed_conversation_id).any? { |_conversation_id, cards| cards.first.id == card.id }
  end
end
