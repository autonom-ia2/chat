export const CRM_VIEW_PERMISSION = 'crm_view';
export const CRM_MANAGE_CARDS_PERMISSION = 'crm_manage_cards';
export const CRM_MOVE_CARDS_PERMISSION = 'crm_move_cards';
export const CRM_MANAGE_PIPELINES_PERMISSION = 'crm_manage_pipelines';
export const CRM_MANAGE_AI_PERMISSION = 'crm_manage_ai';
export const CRM_VIEW_REPORTS_PERMISSION = 'crm_view_reports';
export const CRM_ADMIN_PERMISSION = 'crm_admin';
export const CRM_EXPORT_PERMISSION = 'crm_export';
export const CRM_DELETE_CARDS_PERMISSION = 'crm_delete_cards';
// #1991 — metas do mês por pessoa (gaveta "Metas do mês" em CRM › Números).
export const CRM_METAS_MANAGE_PERMISSION = 'crm_metas_manage';
// #2075 — valores de venda em R$ (valor do card, somas, metas, taxas por valor). Sem ela, contagens e os próprios cards.
export const SALES_VALUE_VIEW_PERMISSION = 'sales_value_view';

// Module keys (#452): `<module>_manage` implies `<module>_view` on the backend, so routes list both.
export const CONTACT_VIEW_PERMISSION = 'contact_view';
export const KNOWLEDGE_BASE_VIEW_PERMISSION = 'knowledge_base_view';
export const AUTONOMIA_PERMISSIONS = ['autonomia_view', 'autonomia_manage'];
// #2251 — painel de desempenho do agente (e a exportação dele): só ver, chave própria, independente de agentes.
export const DESEMPENHO_VIEW_PERMISSION = 'desempenho_view';
export const CONTACT_EXPORT_PERMISSION = 'contact_export';
export const CAMPAIGN_PERMISSIONS = ['campaign_view', 'campaign_manage'];
export const INBOX_PERMISSIONS = ['inbox_view', 'inbox_manage'];
export const CANNED_RESPONSE_MANAGE_PERMISSION = 'canned_response_manage';
// SLA is managed in CRM › SLA (crm_sla_index); the SLA policy API checks this key.
export const SLA_MANAGE_PERMISSION = 'sla_manage';
// Regras de distribuição e capacidade (#1797).
export const ASSIGNMENT_MANAGE_PERMISSION = 'assignment_manage';
export const PROSPECTING_PERMISSIONS = [
  'prospecting_view',
  'prospecting_manage',
];
export const INSURANCE_PERMISSIONS = ['insurance_view', 'insurance_manage'];
export const AUTOMATION_PERMISSIONS = ['automation_view', 'automation_manage'];
export const SCHEDULING_PERMISSIONS = [
  'agendamento_view',
  'agendamento_manage',
];
// Anúncios da Meta (#1794): ver o painel. Conectar, configurar e desconectar: meta_ads_manage (#2070), chave protegida
// (regra das duas listas, #1782): só o administrador entrega, ou quem tem o ajuste 'Pode entregar acima do próprio',
// que só o administrador liga.
export const META_ADS_VIEW_PERMISSION = 'meta_ads_view';
export const META_ADS_MANAGE_PERMISSION = 'meta_ads_manage';
// #2302 — Seus posts: ver os posts e os números das caixas que vê (posts_manage também vê).
export const POSTS_PERMISSIONS = ['posts_view', 'posts_manage'];

// Pessoas (#1931): agentes e times, montar funções, entregar acesso acima do próprio.
export const PEOPLE_MANAGE_PERMISSION = 'people_manage';
export const CUSTOM_ROLE_MANAGE_PERMISSION = 'custom_role_manage';
export const GRANT_ABOVE_OWN_PERMISSION = 'grant_above_own';
// Financeiro (#1969): os custos da conta em dinheiro (uso de IA) e a autorização de cobranças da Meta. Plano e faturas
// seguem só do administrador.
export const FINANCIAL_VIEW_PERMISSION = 'financial_view';
export const FINANCIAL_MANAGE_PERMISSION = 'financial_manage';
// Integrações (#2027): conectar, configurar e desconectar integrações, robôs, importações e trocar a credencial de
// uma caixa que já existe. Criar caixa nova segue com inbox_manage.
export const INTEGRATION_MANAGE_PERMISSION = 'integration_manage';
// Tokens e chaves (#2027): ver e trocar os segredos que a plataforma gera (HMAC, segredo da caixa da API, assinatura de
// webhook, token do robô, tokens do CRM, link do Google).
export const TOKEN_MANAGE_PERMISSION = 'token_manage';
// Espelho de CustomRole::DELEGATION_KEYS: só o administrador entrega, ou quem tem grant_above_own.
export const DELEGATION_KEYS = [
  PEOPLE_MANAGE_PERMISSION,
  CUSTOM_ROLE_MANAGE_PERMISSION,
  GRANT_ABOVE_OWN_PERMISSION,
  FINANCIAL_VIEW_PERMISSION,
  FINANCIAL_MANAGE_PERMISSION,
  INTEGRATION_MANAGE_PERMISSION,
  TOKEN_MANAGE_PERMISSION,
  META_ADS_MANAGE_PERMISSION,
  SALES_VALUE_VIEW_PERMISSION,
];
// Chave que só funciona junto com outra: a meta do mês é dinheiro (#2075). Ligar a primeira liga a segunda, e quem não
// pode entregar a segunda também não entrega a primeira.
export const KEY_DEPENDENCIES = {
  [CRM_METAS_MANAGE_PERMISSION]: SALES_VALUE_VIEW_PERMISSION,
};

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

// Lê as conversas da caixa sem operar (#1800). Não entra em CONVERSATION_PERMISSIONS: essa lista abre também
// respostas prontas, macros e alertas de quem atende.
export const CONVERSATION_VIEW_PERMISSION = 'conversation_view';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
      CONVERSATION_VIEW_PERMISSION,
    ],
  },
};
