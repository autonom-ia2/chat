// Os dois perfis de quem monta da especificação (#2308, seção 4; o mesmo GIVER de calc/cartoes.mjs). Carla não é
// administradora, tem a função "Gerente da loja", campaign_send e contact_delete; não tem crm_export, crm_admin,
// crm_metas_manage, sales_value_view, insurance_*, financeiro nem integrações.
export const CARLA = {
  userId: 9,
  isAdmin: false,
  customRoleId: 7,
  permissions: [
    'custom_role_manage',
    'people_manage',
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
    'conversation_message_delete',
    'contact_manage',
    'contact_export',
    'contact_delete',
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
    'crm_manage_pipelines',
    'crm_manage_ai',
    'crm_delete_cards',
    'crm_view_reports',
    'prospecting_manage',
    'prospecting_view_all_searches',
    'campaign_manage',
    'campaign_send',
    'whatsapp_templates_manage',
    'report_manage',
    'knowledge_base_manage',
    'canned_response_manage',
    'autonomia_manage',
    'inbox_manage',
    'automation_manage',
    'label_manage',
    'attribute_manage',
    'macro_manage',
    'sla_manage',
    'agendamento_manage',
    'assignment_manage',
    'desempenho_view',
    'meta_ads_view',
  ],
};

export const ADMIN = {
  userId: 1,
  isAdmin: true,
  customRoleId: null,
  permissions: [],
};

// Carla sem disparar campanhas: a variante da especificação 5.B3.
export const CARLA_SEM_DISPARO = {
  ...CARLA,
  permissions: CARLA.permissions.filter(chave => chave !== 'campaign_send'),
};

// Função antiga de quem monta: crm_admin e editar as vendas, sem crm_view (a conferência do #2124 só garante
// "crm_view OU crm_admin"). O servidor não deixa ela dar chave de editar as vendas, que traz crm_view.
export const SEM_VER_VENDAS = {
  userId: 12,
  isAdmin: false,
  customRoleId: 11,
  permissions: [
    'custom_role_manage',
    'crm_admin',
    'crm_manage_cards',
    'contact_manage',
  ],
};
