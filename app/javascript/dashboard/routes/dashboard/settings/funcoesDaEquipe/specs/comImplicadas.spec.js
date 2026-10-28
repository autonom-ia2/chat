import { CRM_EDITING_KEYS, comImplicadas } from '../comImplicadas';

// #2308, especificação 14: espelho de CustomRole.with_implied_permissions (custom_role.rb), no padrão de
// useCrmPermissions.spec.js.
describe('comImplicadas', () => {
  it('são as 7 chaves de editar as vendas do servidor', () => {
    expect(CRM_EDITING_KEYS).toEqual([
      'crm_manage_cards',
      'crm_move_cards',
      'crm_manage_pipelines',
      'crm_manage_ai',
      'crm_delete_cards',
      'crm_metas_manage',
      'crm_export',
    ]);
  });

  it.each(CRM_EDITING_KEYS)('%s traz crm_view', chave => {
    expect(comImplicadas([chave])).toEqual([chave, 'crm_view']);
  });

  it('relatórios e R$ não trazem crm_view; quem já tem fica igual', () => {
    expect(comImplicadas(['crm_view_reports', 'sales_value_view'])).toEqual([
      'crm_view_reports',
      'sales_value_view',
    ]);
    expect(comImplicadas(['crm_view', 'crm_export'])).toEqual([
      'crm_view',
      'crm_export',
    ]);
    expect(comImplicadas([])).toEqual([]);
  });
});
