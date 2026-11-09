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

  // #1430: a ferramenta não tem item no menu (fica na página do agente) e diz "Gerenciar".
  it('names the tools level "Gerenciar" and keeps them out of the menu preview', () => {
    const wrapper = mount(RoleSummary, {
      props: { permissions: ['autonomia_view', 'autonomia_tools_manage'] },
      global: { mocks: { $t: t } },
    });

    const toolsLine = wrapper
      .findAll('li')
      .find(item =>
        item.text().includes('CUSTOM_ROLE.MATRIX.MODULES.AUTONOMIA_TOOLS.NAME')
      );
    expect(toolsLine.text()).toContain(
      'cUSTOM_ROLE.MATRIX.MODULES.AUTONOMIA_TOOLS.LEVEL_LABEL_MANAGE'
    );
    const menu = wrapper.find('details').text();
    expect(menu).toContain('CUSTOM_ROLE.MATRIX.MODULES.AUTONOMIA.NAME');
    expect(menu).not.toContain('AUTONOMIA_TOOLS');
  });
});
