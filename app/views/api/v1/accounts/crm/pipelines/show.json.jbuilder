json.payload do
  json.partial! 'api/v1/accounts/crm/pipelines/pipeline', pipeline: @pipeline
  # Arquivar e restaurar o funil (#2095): quantos cards abertos ficam nele, quantos foram para outro funil e quantos
  # retornos marcados dos que ficaram pararam.
  json.open_cards_count @open_cards_count unless @open_cards_count.nil?
  json.moved_cards_count @moved_cards_count unless @moved_cards_count.nil?
  json.stopped_follow_ups_count @stopped_follow_ups_count unless @stopped_follow_ups_count.nil?
  # Arquivar com Mover (#2145): clientes que já tinham card aberto no destino e ficaram com dois. Os primeiros 20 com
  # nome e card, para o resumo listar; o total em count.
  unless @clients_with_two_open.nil?
    json.clients_with_two_open do
      json.count @clients_with_two_open.size
      json.items @clients_with_two_open.first(20)
    end
  end
  # Arquivar (decisão 7): as caixas que foram para outro funil, e qual (nil quando ficaram neste).
  unless @moved_inboxes.nil?
    json.moved_inboxes @moved_inboxes
    json.inboxes_target_pipeline_id @inboxes_target_pipeline_id
  end
end
