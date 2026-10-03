import { mount } from '@vue/test-utils';
import RoleSummary from '../component/RoleSummary.vue';

const MESSAGES = {
  'CUSTOM_ROLE.MATRIX.LEVELS.MANAGE': 'Editar',
  'CUSTOM_ROLE.PERMISSIONS.CRM_VIEW_REPORTS': 'Visualizar relatórios do CRM',
  'CUSTOM_ROLE.SEPARATORS.COMMA': ',',
};
const t = key => MESSAGES[key] || key;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

describe('RoleSummary', () => {
  it('joins level and options without a space before the comma and keeps acronyms', () => {
    const wrapper = mount(RoleSummary, {
      props: {
        permissions: ['crm_view', 'crm_manage_cards', 'crm_view_reports'],
      },
      global: { mocks: { $t: t } },
    });

    const crmLine = wrapper
      .findAll('li')
      .find(item =>
        item.text().includes('CUSTOM_ROLE.MATRIX.MODULES.CRM.NAME')
      );

    expect(crmLine.text()).toContain('editar, visualizar relatórios do CRM');
    expect(crmLine.text()).not.toContain(' ,');
  });
});
