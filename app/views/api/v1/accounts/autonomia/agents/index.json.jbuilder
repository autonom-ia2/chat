json.payload do
  json.array! @agents do |agent|
    json.partial! 'api/v1/accounts/autonomia/agents/agent', agent: agent, list_row: @list_projection.fetch(agent.id)
  end
end

# The FE store factory's SET_META mutation reads meta.total_count/meta.page on
# every list load; without a meta block it throws and the Hub shows a load error.
json.meta do
  json.total_count @agents.size
  json.page 1
end

json.copilot_availability do
  json.available @copilot_availability.fetch(:available)
  json.can_choose_internal @copilot_availability.fetch(:can_choose_internal)
  json.reasons @copilot_availability.fetch(:reasons)
end
