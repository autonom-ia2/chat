json.payload do
  json.partial! 'api/v1/accounts/autonomia/agents/sources/source',
                source: @source, material_projection: @material_projection
end
