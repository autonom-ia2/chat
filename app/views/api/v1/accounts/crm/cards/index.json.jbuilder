conversation_visibility = Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)
conversation_visibility.preload_cards(@cards.to_a)
# Lista nova (#2283): o retorno de todos os cards da página numa consulta; a Lista legada não paga a consulta.
next_follow_ups = (Crm::FollowUp.proximos_retornos_da_pessoa(@cards.map(&:id), conversation_visibility: conversation_visibility) if @action_list)

json.payload do
  json.array! @cards do |card|
    json.merge! Crm::Cards::PayloadBuilder.new(
      card,
      user: Current.user,
      account_user: Current.account_user,
      conversation_visibility: conversation_visibility,
      company: @card_companies[card.id],
      next_follow_up: next_follow_ups ? next_follow_ups[card.id] : Crm::Cards::PayloadBuilder::SKIP_FOLLOW_UP
    ).perform
  end
end

json.meta do
  json.count @cards_count
end
