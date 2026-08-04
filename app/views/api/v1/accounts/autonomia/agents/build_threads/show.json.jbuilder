json.payload do
  json.id @thread.id
  json.agent_id @thread.autonomia_agent_id
  json.status @thread.status
  json.messages @thread.messages
  # IP oculto: o `state.draft_config` pode conter instruction/scaffold gerados pelo Construtor —
  # NUNCA expor. Só liberamos os campos de progresso da conversa, explicitamente filtrados.
  json.state do
    json.needs_more_info @thread.state['needs_more_info']
    json.next_question @thread.state['next_question']
    json.turn @thread.state['turn']
    # GAP (A) — o FE usa para o gate "não tenho material" (decisão do usuário de avançar a etapa de
    # materiais sem subir nada). Lido do jsonb `state`; campo seguro (não é IP).
    json.no_materials_declared ActiveModel::Type::Boolean.new.cast(@thread.state['no_materials_declared']) || false
    # FALHA NUNCA SILENCIOSA: sem isto o front só sabia "failed" e mandava o dono reenviar a mensagem —
    # orientação errada numa falha determinística (o mesmo texto falharia de novo). `error` é o código do
    # erro, `error_fields`/`truncated_fields` são NOMES DE COLUNA e `applied` diz se algo foi gravado no
    # agente. Todos seguros; o `draft_config` (IP oculto) segue fora daqui.
    json.error @thread.state['error']
    json.error_fields Array(@thread.state['error_fields'])
    json.truncated_fields Array(@thread.state['truncated_fields'])
    json.applied @thread.state['applied']
  end
  json.created_at @thread.created_at
  json.updated_at @thread.updated_at
end
