json.payload do
  json.partial! 'api/v1/accounts/crm/pipelines/pipeline', pipeline: @pipeline
  # Arquivar e restaurar o funil (#2095): quantos cards abertos ficam nele e quantos foram para outro funil.
  json.open_cards_count @open_cards_count unless @open_cards_count.nil?
  json.moved_cards_count @moved_cards_count unless @moved_cards_count.nil?
end
