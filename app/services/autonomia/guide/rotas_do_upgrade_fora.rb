# Upgrade 4.19.1 (#3119): rotas da conta que o Chatwoot trouxe para recursos que esta instalação não usa — monitores
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
    'POST integrations/shopify/complete_install'
  ].freeze
end
