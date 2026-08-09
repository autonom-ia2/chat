json.payload do
  json.array! @stages do |stage|
    json.partial! 'api/v1/accounts/crm/stages/stage', stage: stage,
                                                        total_cards_count: @cards_count_by_stage.fetch(stage.id, 0)
  end
end

json.meta do
  json.count @stages_count
end
