import { mount } from '@vue/test-utils';
import PermissionRow from '../component/PermissionRow.vue';
import PermissionGroup from '../component/PermissionGroup.vue';
import ProfilePicker from '../component/ProfilePicker.vue';
import { MODULE_GROUPS, moduleByKey } from '../permissionMatrix';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const global = {
  mocks: {
    $t: (key, params) => (params?.name ? `${key}:${params.name}` : key),
  },
};

const radios = wrapper => wrapper.findAll('[role="radio"]');
const checked = wrapper =>
  radios(wrapper).find(radio => radio.attributes('aria-checked') === 'true');

describe('PermissionRow', () => {
  const mountRow = (moduleKey, permissions, props = {}) =>
    mount(PermissionRow, {
      props: { module: moduleByKey(moduleKey), permissions, ...props },
      global,
    });

  it('marks the saved level and keeps three positions', () => {
    const wrapper = mountRow('CAMPAIGNS', ['campaign_view']);

    expect(radios(wrapper)).toHaveLength(3);
    expect(checked(wrapper).text()).toBe('CUSTOM_ROLE.MATRIX.LEVELS.VIEW');
    expect(checked(wrapper).classes()).toContain('font-semibold');
  });

  it('fills the missing level with a placeholder, not a button', () => {
    const wrapper = mountRow('CANNED_RESPONSES', []);

    expect(radios(wrapper)).toHaveLength(2);
    expect(wrapper.find('[aria-hidden="true"]').text()).toBe(
      'CUSTOM_ROLE.SEPARATORS.NONE'
    );
    expect(checked(wrapper).text()).toBe('CUSTOM_ROLE.MATRIX.BASELINE.USE');
  });

  // Seus posts oferece editar desde a F2 (#2305): responder, esconder, apagar e o privado.
  it('offers posts edit to a new role', () => {
    expect(radios(mountRow('POSTS', ['posts_view']))).toHaveLength(3);
  });

  it('marks posts edit for a role that has it', () => {
    const wrapper = mountRow('POSTS', ['posts_manage']);

    expect(radios(wrapper)).toHaveLength(3);
    expect(checked(wrapper).text()).toBe('CUSTOM_ROLE.MATRIX.LEVELS.MANAGE');
  });

  it('emits the chosen level', async () => {
    const wrapper = mountRow('INBOXES', []);

    await radios(wrapper)[2].trigger('click');

    expect(wrapper.emitted('selectLevel')[0]).toEqual(['manage']);
  });

  it('moves the selection with the arrow keys', async () => {
    const wrapper = mountRow('INBOXES', ['inbox_view']);

    await checked(wrapper).trigger('keydown', { key: 'ArrowRight' });

    expect(wrapper.emitted('selectLevel')[0]).toEqual(['manage']);
  });

  it('hides fine-tuning until the module has access', () => {
    expect(mountRow('CRM', []).text()).not.toContain(
      'CUSTOM_ROLE.EDITOR.FINE_TUNING'
    );
    expect(mountRow('CRM', ['crm_view']).text()).toContain(
      'CUSTOM_ROLE.EDITOR.FINE_TUNING'
    );
  });

  it('flags sensitive extras and emits toggles', async () => {
    const wrapper = mountRow('CRM', ['crm_view'], { isOpen: true });

    expect(wrapper.text()).toContain('CUSTOM_ROLE.EDITOR.SENSITIVE');
    await wrapper.find('[role="switch"]').trigger('click');

    expect(wrapper.emitted('toggleExtra')[0]).toEqual(['crm_move_cards']);
  });

  it('locks the options included in full CRM access', () => {
    const wrapper = mountRow('CRM', ['crm_view', 'crm_admin', 'crm_export'], {
      isOpen: true,
    });
    const exportRow = wrapper
      .findAll('li')
      .find(item => item.text().includes('CUSTOM_ROLE.PERMISSIONS.CRM_EXPORT'));

    expect(exportRow.find('[role="switch"]').attributes()).toHaveProperty(
      'disabled'
    );
    expect(exportRow.text()).toContain('CUSTOM_ROLE.EDITOR.INCLUDED_IN_ADMIN');
  });

  it('offers to grant campaigns when prospecting needs it', async () => {
    const wrapper = mountRow('PROSPECTING', ['prospecting_manage']);

    expect(wrapper.text()).toContain(
      'CUSTOM_ROLE.MATRIX.MODULES.PROSPECTING.SUGGESTION'
    );
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CUSTOM_ROLE.EDITOR.GRANT_SUGGESTED')
      .trigger('click');

    expect(wrapper.emitted('grantSuggested')[0][0].key).toBe('CAMPAIGNS');
  });
});

describe('PermissionRow com chaves fora do alcance (#1931)', () => {
  const keyLock = key => {
    if (
      ['people_manage', 'custom_role_manage', 'grant_above_own'].includes(key)
    )
      return 'DELEGATION';
    return key === 'inbox_manage' ? 'MISSING' : null;
  };
  const mountRow = (moduleKey, permissions, props = {}) =>
    mount(PermissionRow, {
      props: { module: moduleByKey(moduleKey), permissions, keyLock, ...props },
      global,
    });

  it('locks a level that would add a missing key, with the reason written', async () => {
    const wrapper = mountRow('INBOXES', ['inbox_view']);
    const manage = radios(wrapper)[2];

    expect(manage.attributes('aria-disabled')).toBe('true');
    expect(wrapper.find('[data-row-lock]').text()).toBe(
      'CUSTOM_ROLE.EDITOR.LOCK.MISSING'
    );
    await manage.trigger('click');
    await checked(wrapper).trigger('keydown', { key: 'ArrowRight' });

    expect(wrapper.emitted('selectLevel')[0]).toEqual(['none']);
  });

  it('locks People for whoever cannot grant above their own access', () => {
    const wrapper = mountRow('PEOPLE', []);

    expect(radios(wrapper)[1].attributes('aria-disabled')).toBe('true');
    expect(wrapper.find('[data-row-lock]').text()).toBe(
      'CUSTOM_ROLE.EDITOR.LOCK.DELEGATION'
    );
  });

  it('keeps removing always possible', async () => {
    const wrapper = mountRow('INBOXES', ['inbox_view']);

    await radios(wrapper)[0].trigger('click');

    expect(wrapper.emitted('selectLevel')[0]).toEqual(['none']);
  });

  it('disables a fine-tuning switch whose key is out of reach', () => {
    const wrapper = mountRow('PEOPLE', ['people_manage'], {
      isOpen: true,
      keyLock: key => (key === 'people_manage' ? null : keyLock(key)),
    });
    const switches = wrapper.findAll('[role="switch"]');

    expect(switches).toHaveLength(2);
    switches.forEach(item =>
      expect(item.attributes()).toHaveProperty('disabled')
    );
    expect(wrapper.text()).toContain('CUSTOM_ROLE.EDITOR.LOCK.DELEGATION');
  });

  it('shows nothing locked to an administrator', () => {
    const wrapper = mount(PermissionRow, {
      props: { module: moduleByKey('PEOPLE'), permissions: [] },
      global,
    });

    expect(wrapper.find('[data-row-lock]').exists()).toBe(false);
    expect(radios(wrapper)[1].attributes('aria-disabled')).toBeUndefined();
  });
});

describe('PermissionGroup', () => {
  const group = MODULE_GROUPS.find(item => item.key === 'SERVICE');

  it('shows a one-line summary while closed', () => {
    const wrapper = mount(PermissionGroup, {
      props: {
        group,
        modules: group.modules,
        permissions: ['conversation_manage', 'contact_view'],
      },
      global,
    });

    expect(wrapper.findAllComponents(PermissionRow)).toHaveLength(0);
    expect(wrapper.text()).toContain('CUSTOM_ROLE.MATRIX.LEVELS.ALL');
    expect(wrapper.text()).toContain('CUSTOM_ROLE.MATRIX.LEVELS.VIEW');
  });

  it('lists the rows once open', () => {
    const wrapper = mount(PermissionGroup, {
      props: { group, modules: group.modules, permissions: [], isOpen: true },
      global,
    });

    expect(wrapper.findAllComponents(PermissionRow)).toHaveLength(
      group.modules.length
    );
  });
});

describe('ProfilePicker', () => {
  it('starts with a profile selected and emits it on continue', async () => {
    const wrapper = mount(ProfilePicker, {
      props: { initialProfile: 'SUPERVISOR' },
      global,
    });

    expect(checked(wrapper).attributes('data-profile')).toBe('SUPERVISOR');
    expect(wrapper.text()).toContain('CUSTOM_ROLE.PICKER.CAN');

    await wrapper.find('[data-profile="SDR"]').trigger('click');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('CUSTOM_ROLE.PICKER.CONTINUE'))
      .trigger('click');

    expect(wrapper.emitted('choose')[0]).toEqual(['SDR']);
  });

  it('moves between profiles with the arrow keys', async () => {
    const wrapper = mount(ProfilePicker, {
      props: { initialProfile: 'AGENT' },
      global,
    });

    await wrapper.find('[role="radiogroup"]').trigger('keydown.down');

    expect(checked(wrapper).attributes('data-profile')).toBe('SUPERVISOR');
  });

  // #2115: a prévia conta só o que o modelo vai aplicar para quem está montando.
  it('counts only the areas and sensitive keys within reach', () => {
    const counted = {
      mocks: {
        $t: (key, count) =>
          typeof count === 'number' ? `${key}#${count}` : key,
      },
    };
    const full = mount(ProfilePicker, {
      props: { initialProfile: 'SALES_MANAGER' },
      global: counted,
    });
    const reduced = mount(ProfilePicker, {
      props: {
        initialProfile: 'SALES_MANAGER',
        reach: keys =>
          keys.filter(
            key => !['sales_value_view', 'crm_metas_manage'].includes(key)
          ),
      },
      global: counted,
    });
    const finance = mount(ProfilePicker, {
      props: {
        initialProfile: 'FINANCE',
        reach: keys => keys.filter(key => key !== 'financial_view'),
      },
      global: counted,
    });

    expect(full.text()).toContain('CUSTOM_ROLE.SUMMARY.SENSITIVE#3');
    expect(reduced.text()).toContain('CUSTOM_ROLE.SUMMARY.SENSITIVE#1');
    expect(finance.text()).toContain('CUSTOM_ROLE.PICKER.AREAS#2');
    expect(full.text()).not.toContain('CUSTOM_ROLE.PICKER.LEFT_OUT');
    expect(reduced.text()).toContain('CUSTOM_ROLE.PICKER.LEFT_OUT');
  });
});
