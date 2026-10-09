json.id source.id
json.autonomia_agent_id source.autonomia_agent_id
# GAP (A) — grupo do material: 'knowledge' (o que ela sabe) | 'media' (o que ela envia). O FE
# renderiza a 2ª aba "O que ela pode enviar" filtrando por kind. NUNCA expõe instruction/scaffold.
json.kind source.kind
json.source_type source.source_type
json.reference source.reference
json.external_link source.external_link
json.status source.status
json.sync_status source.sync_status
json.error source.error
json.metadata do
  json.chunk_count source.metadata['chunk_count']
  json.byte_size source.metadata['byte_size']
  json.mime source.metadata['mime']
end
# Revisor v2: parecer da IA Revisora por fonte (nota/confiança/recomendação/resumo). NUNCA expõe a
# REVIEWER_INSTRUCTION. nil em fontes antigas / ainda não revisadas.
json.review do
  json.quality_score source.quality_score
  json.confidence source.confidence
  json.status source.review_status
  json.label source.review_label
  json.reason source.review_reason
  json.summary source.review_summary
  json.reviewed_at source.reviewed_at
end
json.synced_at source.synced_at
json.created_at source.created_at
json.updated_at source.updated_at

material_projection = local_assigns[:material_projection]
unless material_projection
  material_projection = Autonomia::Agents::MaterialProjection.new(
    agent: source.agent, sources: [source]
  ).call
end
decision = material_projection.decision_for(source)
if decision
  json.screen_state decision[:screen_state]
  json.uses decision[:uses]
  json.uses_reason decision[:uses_reason]
end
