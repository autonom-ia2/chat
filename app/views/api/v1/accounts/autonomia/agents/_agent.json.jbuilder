json.id agent.id
json.name agent.name
json.voice Autonomia::Agents::Config::VOICE_BY_GENDER.key(Autonomia::Agents::Config.voice_for(agent))
json.avatar_url agent.avatar_url
json.agent_type agent.agent_type
# V2.1 — onde o agente atua (external/internal/both) + se declarou ter base de conhecimento.
json.actuation agent.actuation
json.with_knowledge agent.with_knowledge != false
json.status agent.status
json.mode agent.mode
json.human_card agent.human_card
json.greeting agent.greeting
json.fallback_message agent.fallback_message
json.handoff_rule agent.handoff_rule
json.starter_questions agent.starter_questions
json.tone agent.tone
# ALLOWLIST do jsonb `config`: só as chaves que o FE consome (PanelTune/PanelKnowledge/PanelPublish
# leem handoff_strategy/confidence_threshold/knowledge_confidence; with_knowledge/knowledge_summary
# acompanham por contrato). Chaves INTERNAS (knowledge_refresh_token, builder_active_thread_id,
# system_key, guide_*, test_allowlist_phones, topic_map bruto...) NUNCA saem por aqui.
# `audience`/`response_window` (#284 · Entrega 2a): público-alvo e horário de atuação (PanelTune).
# `audience_unknown_contact`: o que fazer com conversa sem contato quando há público-alvo.
# `faq_suggestions` (#284 · 2b): toggle da geração de sugestões de FAQ (aba Conhecimento).
json.config agent.config.to_h.slice('handoff_strategy', 'handoff_target_type', 'handoff_target_id', 'confidence_threshold',
                                    'with_knowledge', 'knowledge_confidence', 'knowledge_summary',
                                    'audience', 'response_window', 'audience_unknown_contact',
                                    'faq_suggestions')
json.draft_retention_hours Autonomia::Agents::Config.draft_reap_hours
# Revisor v2: MAPA DE TEMAS + confiança geral + resumo da base (UI de Conhecimento). Seguros de
# expor (vêm do jsonb `config`, NUNCA de instruction/scaffold). Já estão dentro de `config`; expô-los
# no topo dá chaves estáveis ao FE.
json.topic_map Array(agent.topic_map)
json.knowledge_confidence agent.knowledge_confidence
json.knowledge_summary agent.knowledge_summary
# BE-17 — a aba O que sabe da Lia lê esta projeção pela porta de Agentes. Não chamar
# `insurance/*` aqui: `autonomia_view` deve ver os ramos mesmo sem `insurance_view`.
if local_assigns.fetch(:detail, false) && agent.instrucao_mantida?
  escolhas = agent.config.to_h[Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA].to_h
  json.instrucao_mantida true
  json.quote_choices do
    json.name escolhas['nome_agente']
    json.behavior escolhas['comportamento']
    json.horario escolhas['horario']
  end
  disponiveis = agent.specialists.enabled.order(:id).select do |specialist|
    Autonomia::Insurance::QuoteAgent::Builder.disponivel?(specialist)
  end
  json.quote_branches(disponiveis.map { |specialist| { slug: specialist.slug, name: specialist.name } })
end
json.enabled agent.enabled
# #647 — canais (inboxes) ligados ao agente, lido pelo cartão. `size` usa o preload da listagem
# (index, sem N+1) e só faz um COUNT no detalhe.
if local_assigns.key?(:list_row)
  json.channels_count list_row.fetch(:channels).size
  json.state list_row.fetch(:state)
  json.channels list_row.fetch(:channels)
  json.copilot_available list_row.fetch(:copilot_available)
  json.stats list_row[:stats] if list_row.key?(:stats)
else
  json.channels_count agent.agent_inboxes.kept.size
end
# IP oculto: `scaffold` JAMAIS é exposto. `instruction` só aparece em modo manual (texto do
# próprio usuário, visível); em modo guiado a instrução é gerada pelo Construtor e permanece oculta.
json.instruction agent.instruction if agent.manual? && (!local_assigns.key?(:list_row) || local_assigns[:detail])
json.writes_external local_assigns.fetch(:writes_external) if local_assigns.fetch(:detail, false)
json.has_guided_version agent.guided_version? if local_assigns.fetch(:detail, false)
# #3 INSTRUÇÃO VIVA (C): booleano SEGURO (NUNCA o texto) para o FE saber se um agente guiado já tem
# instrução (foi finalizado). Usado pelo PanelTest para avisar que um rascunho não-finalizado ainda
# não reflete o comportamento real. IP OCULTO preservado: expõe presença, não conteúdo.
json.has_instruction agent.instruction.present?
json.created_at agent.created_at
json.updated_at agent.updated_at
