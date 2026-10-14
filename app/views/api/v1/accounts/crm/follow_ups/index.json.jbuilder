conversation_visibility = Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)
conversation_visibility.preload(@follow_ups.map(&:conversation))

json.payload do
  json.array! @follow_ups do |follow_up|
    json.partial!(
      'api/v1/accounts/crm/follow_ups/follow_up',
      follow_up: follow_up,
      conversation_visibility: conversation_visibility
    )
  end
end
json.meta do
  json.count @follow_ups_count
  if @follow_ups.respond_to?(:current_page)
    json.current_page @follow_ups.current_page
    json.total_pages @follow_ups.total_pages
  end
end
