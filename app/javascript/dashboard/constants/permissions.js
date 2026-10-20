export const CRM_VIEW_PERMISSION = 'crm_view';
export const CRM_MANAGE_CARDS_PERMISSION = 'crm_manage_cards';
export const CRM_MOVE_CARDS_PERMISSION = 'crm_move_cards';
export const CRM_MANAGE_PIPELINES_PERMISSION = 'crm_manage_pipelines';
export const CRM_MANAGE_AI_PERMISSION = 'crm_manage_ai';
export const CRM_VIEW_REPORTS_PERMISSION = 'crm_view_reports';
export const CRM_ADMIN_PERMISSION = 'crm_admin';
export const CRM_EXPORT_PERMISSION = 'crm_export';
export const CRM_DELETE_CARDS_PERMISSION = 'crm_delete_cards';

// Module keys (#452): `<module>_manage` implies `<module>_view` on the backend, so routes list both.
export const CONTACT_VIEW_PERMISSION = 'contact_view';
export const KNOWLEDGE_BASE_VIEW_PERMISSION = 'knowledge_base_view';
export const AUTONOMIA_PERMISSIONS = ['autonomia_view', 'autonomia_manage'];
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
// Anúncios da Meta (#1794): ver o painel. Conectar e configurar seguem só do administrador.
export const META_ADS_VIEW_PERMISSION = 'meta_ads_view';

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
