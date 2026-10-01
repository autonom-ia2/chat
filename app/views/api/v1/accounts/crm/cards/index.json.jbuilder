conversation_visibility = Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)

json.payload do
  json.array! @cards do |card|
    json.merge! Crm::Cards::PayloadBuilder.new(
      card,
      user: Current.user,
      account_user: Current.account_user,
      conversation_visibility: conversation_visibility,
      company: @card_companies[card.id]
    ).perform
  end
end

json.meta do
  json.count @cards_count
end
