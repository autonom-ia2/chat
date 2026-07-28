json.payload do
  json.array! @tools, partial: 'api/v1/accounts/autonomia/agents/tools/tool', as: :tool
end
