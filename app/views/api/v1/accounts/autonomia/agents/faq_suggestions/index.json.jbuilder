json.meta do
  json.count @total_count
  json.pending_count @pending_count
  json.current_page @current_page
  json.per_page Api::V1::Accounts::Autonomia::Agents::FaqSuggestionsController::RESULTS_PER_PAGE
end
json.payload do
  json.array! @suggestions, partial: 'api/v1/accounts/autonomia/agents/faq_suggestions/faq_suggestion', as: :suggestion
end
