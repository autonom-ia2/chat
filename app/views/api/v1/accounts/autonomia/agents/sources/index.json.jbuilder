json.payload do
  json.array! @sources do |source|
    json.partial! 'api/v1/accounts/autonomia/agents/sources/source',
                  source: source, material_projection: @material_projection
  end
end

# Defensive: mirror the agents index so any future factory `get` (which commits
# SET_META reading meta.total_count/meta.page) doesn't throw. The custom `fetch`
# path ignores this block.
json.meta do
  json.total_count @sources.size
  json.page 1
end
