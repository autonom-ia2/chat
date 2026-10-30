json.payload do
  json.partial! 'api/v1/accounts/crm/pipelines/pipeline', pipeline: @pipeline
  # Arquivar e restaurar o funil (#2095): quantos cards abertos ficam nele, quantos foram para outro funil e quantos
  # retornos marcados dos que ficaram pararam.
  json.open_cards_count @open_cards_count unless @open_cards_count.nil?
  json.moved_cards_count @moved_cards_count unless @moved_cards_count.nil?
  json.stopped_follow_ups_count @stopped_follow_ups_count unless @stopped_follow_ups_count.nil?
  # Arquivar com Mover (#2145): clientes que já tinham card aberto no destino e ficaram com mais de um. count é de
  # todos; items, até 20 com nome e card, só dos que a pessoa vê no CRM (PipelineArchiving#visible_clients_with_two_open).
  unless @clients_with_two_open.nil?
    json.clients_with_two_open do
      json.count @clients_with_two_open_count
      json.items @clients_with_two_open
    end
  end
  # Arquivar (decisão 7): as caixas que foram para outro funil, e qual (nil quando ficaram neste).
  unless @moved_inboxes.nil?
    json.moved_inboxes @moved_inboxes
    json.inboxes_target_pipeline_id @inboxes_target_pipeline_id
  end
end
