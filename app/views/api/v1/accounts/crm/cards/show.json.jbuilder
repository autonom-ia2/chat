json.payload do
  json.merge! Crm::Cards::DetailPayloadBuilder.new(
    card: @card,
    user: Current.user,
    account_user: Current.account_user
  ).perform
end
# Só no reset do follow-up (chat#1325): o que aconteceu com a recusa do contato. Valores em
# CardsController#release_follow_up_reply: released, kept_other_cards, kept_other_source, kept_no_permission, none.
json.contact_opt_out @contact_opt_out if @contact_opt_out
