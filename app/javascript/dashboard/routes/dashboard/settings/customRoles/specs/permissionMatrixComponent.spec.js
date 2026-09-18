import { mount } from '@vue/test-utils';
import PermissionMatrix from '../component/PermissionMatrix.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

let wrapper;

const mountMatrix = permissions => {
  wrapper = mount(PermissionMatrix, {
    props: {
      modelValue: permissions,
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
    global: { mocks: { $t: key => key } },
  });
};

const rowFor = moduleKey =>
  wrapper
    .findAll('.border-t')
    .find(row =>
      row.text().includes(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.NAME`)
    );

const buttonIn = (element, label) =>
  element.findAll('button').find(button => button.text() === label);

describe('PermissionMatrix', () => {
  it('marks the saved level of each module as active', () => {
    mountMatrix(['campaign_manage']);

    const active = rowFor('CAMPAIGNS')
      .findAll('button')
      .find(button => button.classes().includes('text-n-blue-11'));
    expect(active.text()).toBe('CUSTOM_ROLE.MATRIX.LEVELS.MANAGE');
  });

  it('emits the module key when a level is picked', async () => {
    mountMatrix([]);

    await buttonIn(rowFor('INBOXES'), 'CUSTOM_ROLE.MATRIX.LEVELS.VIEW').trigger(
      'click'
    );

    expect(wrapper.props('modelValue')).toEqual(['inbox_view']);
  });

  it('shows CRM options only once the CRM has access', async () => {
    mountMatrix([]);
    expect(rowFor('CRM').text()).not.toContain('CRM_MANAGE_AI');

    await buttonIn(rowFor('CRM'), 'CUSTOM_ROLE.MATRIX.LEVELS.VIEW').trigger(
      'click'
    );
    await buttonIn(
      rowFor('CRM'),
      'CUSTOM_ROLE.PERMISSIONS.CRM_MANAGE_AI'
    ).trigger('click');

    expect(wrapper.props('modelValue')).toEqual(['crm_view', 'crm_manage_ai']);
  });

  it('replaces every module with a preset', async () => {
    mountMatrix(['inbox_manage']);

    await buttonIn(wrapper, 'CUSTOM_ROLE.MATRIX.PRESETS.MARKETING').trigger(
      'click'
    );

    expect(wrapper.props('modelValue')).toContain('campaign_manage');
    expect(wrapper.props('modelValue')).not.toContain('inbox_manage');
  });
});
