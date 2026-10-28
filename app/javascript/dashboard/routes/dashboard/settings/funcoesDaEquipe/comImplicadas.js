// Espelho de CustomRole.with_implied_permissions (enterprise/app/models/custom_role.rb, #2124): uma chave de editar
// as vendas traz crm_view, e é assim que o servidor grava e confere o alcance de quem dá (GrantGuard#reach?).
export const CRM_EDITING_KEYS = [
  'crm_manage_cards',
  'crm_move_cards',
  'crm_manage_pipelines',
  'crm_manage_ai',
  'crm_delete_cards',
  'crm_metas_manage',
  'crm_export',
];

export const comImplicadas = (permissions = []) => {
  if (permissions.includes('crm_view')) return permissions;
  if (!permissions.some(key => CRM_EDITING_KEYS.includes(key)))
    return permissions;
  return [...permissions, 'crm_view'];
};
