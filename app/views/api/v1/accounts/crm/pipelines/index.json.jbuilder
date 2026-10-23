json.payload do
  json.array! @pipelines do |pipeline|
    json.partial! 'api/v1/accounts/crm/pipelines/pipeline', pipeline: pipeline
    # Funis arquivados (#2095): quantos cards abertos voltam ao quadro se o funil for restaurado, quantos cards ele tem
    # ao todo e as caixas que criam card nele (auto_create_card).
    next unless @open_cards_counts

    json.open_cards_count @open_cards_counts[pipeline.id].to_i
    json.cards_count @cards_counts[pipeline.id].to_i
    json.inboxes @auto_create_inboxes.fetch(pipeline.id, [])
  end
end

json.meta do
  json.count @pipelines_count
end
