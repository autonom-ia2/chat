# Upgrades 4.19.1 (#3119) e 4.20.1 (#3120): rotas da conta que o Chatwoot trouxe para recursos que esta instalação não usa — monitores
# de conversa, Stripe, ferramentas e execuções do Captain, sugestões de etiqueta e prioridade, histórico de campanha,
# tradução automática, enriquecimento de empresa e horário de chamadas. Ficam fora do alcance do Guia, para ele ler e
# fazer o mesmo que antes do upgrade.
#
# O catálogo de leitura vai inteiro em toda pergunta (`Guide::Chat#catalogos`), e a pergunta tem teto
# (`MAX_COMPOSED_QUERY_CHARS`): as ~440 letras destas rotas empurravam o bloco de memória (#933) para fora dele.
module Autonomia::Guide::RotasDoUpgradeFora
  ACOES = [
    'GET monitors', 'POST monitors', 'GET monitors/:id', 'PATCH monitors/:id', 'PUT monitors/:id', 'DELETE monitors/:id',
    'POST monitors/preview', 'GET monitors/preview/:token', 'GET monitors/:id/timeseries', 'GET monitors/:id/conversations',
    'POST monitors/:id/retry_evaluations', 'POST monitors/:id/resume',
    'GET captain/assistants/:assistant_id/stats/drilldown',
    'POST captain/copilot_runs/:id/approve', 'POST captain/copilot_runs/:id/reject',
    'GET captain/tools_manifest/installed', 'POST captain/tools_manifest/preview', 'POST captain/tools_manifest/install',
    'POST saml_settings/refresh',
    'GET conversations/:conversation_id/campaign_history',
    'POST conversations/:conversation_id/messages/auto_translate',
    'GET conversations/:conversation_id/contact_info_request',
    'GET conversations/:conversation_id/suggestions/labels', 'GET conversations/:conversation_id/suggestions/priority',
    'POST companies/:company_id/conversations/filter', 'POST companies/:company_id/enrichment',
    'PATCH inboxes/:inbox_id/call_business_hours', 'PUT inboxes/:inbox_id/call_business_hours',
    'GET integrations/stripe', 'DELETE integrations/stripe', 'POST integrations/stripe/auth', 'GET integrations/stripe/customer',
    'POST integrations/shopify/complete_install',
    # Upgrade 4.20.1 (#3120): MCP e Shopify próprio atrás de flag desligada; Captain e Copilot sem uso; dados (importar,
    # exportar) e prévia de artigo neutralizados; locale do portal, que o fork não deixa editar (#501/#502); horário,
    # roteamento, avisos e conferência de chamadas.
    'GET captain/mcp_servers', 'POST captain/mcp_servers', 'POST captain/mcp_servers/discover',
    'GET captain/mcp_servers/:id', 'PATCH captain/mcp_servers/:id', 'PUT captain/mcp_servers/:id', 'DELETE captain/mcp_servers/:id',
    'GET captain/mcp_servers/:id/authorization_url', 'GET captain/mcp_servers/:id/live_tools',
    'POST captain/mcp_servers/:id/approve_tool',
    'DELETE captain/assistants/:id/avatar', 'DELETE captain/tools_manifest/uninstall', 'POST captain/copilot_threads/:id/stop',
    'GET integrations/shopify_custom_app', 'POST integrations/shopify_custom_app', 'PATCH integrations/shopify_custom_app',
    'PUT integrations/shopify_custom_app', 'DELETE integrations/shopify_custom_app',
    'GET data_exports', 'POST data_exports', 'GET data_exports/:id', 'GET data_exports/:id/download', 'POST data_exports/:id/rerun',
    'GET data_imports/:id/rejected_rows',
    'GET portals/:portal_id/articles/:id/preview_token', 'DELETE portals/:id/remove_locale',
    'GET inboxes/:inbox_id/whatsapp_call_hours', 'PATCH inboxes/:inbox_id/whatsapp_call_hours', 'PUT inboxes/:inbox_id/whatsapp_call_hours',
    'PATCH inboxes/:inbox_id/call_announcements/:kind', 'PUT inboxes/:inbox_id/call_announcements/:kind',
    'PATCH inboxes/:inbox_id/call_routing', 'PUT inboxes/:inbox_id/call_routing',
    'PATCH inboxes/:inbox_id/conference/hold', 'POST inboxes/:inbox_id/conference/dismiss', 'POST whatsapp_calls/:id/dismiss'
  ].freeze
end
