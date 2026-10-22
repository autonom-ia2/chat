json.payload do
  json.array! @pipelines do |pipeline|
    json.partial! 'api/v1/accounts/crm/pipelines/pipeline', pipeline: pipeline
    # Funis arquivados (#2095): quantos cards abertos voltam ao quadro se o funil for restaurado.
    json.open_cards_count @open_cards_counts[pipeline.id].to_i if @open_cards_counts
  end
end

json.meta do
  json.count @pipelines_count
end
