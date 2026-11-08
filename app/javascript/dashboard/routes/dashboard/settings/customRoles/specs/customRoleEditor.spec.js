import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { h } from 'vue';
import CustomRoleEditor from '../CustomRoleEditor.vue';
import ProfilePicker from '../component/ProfilePicker.vue';
import PermissionGroup from '../component/PermissionGroup.vue';
import { MODULES } from '../permissionMatrix';

const route = { params: {}, query: {} };
const router = { push: vi.fn(), replace: vi.fn() };
const alerts = [];

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => router,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (params?.name) return `${key}:${params.name}`;
      if (params?.areas) return `${key}:${params.areas}`;
      return key;
    },
  }),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));

const dialogCalls = { open: 0, close: 0 };
// Stubs como objetos simples: são dublês do teste, não componentes do arquivo.
const DialogStub = {
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
  },
  emits: ['confirm'],
  setup(props, { expose, emit }) {
    expose({
      open: () => {
        dialogCalls.open += 1;
      },
      close: () => {
        dialogCalls.close += 1;
      },
    });
    return () =>
      h('div', { class: 'dialog-stub' }, [
        h('span', props.title),
        h('span', props.description),
        h('button', {
          class: 'dialog-confirm',
          onClick: () => emit('confirm'),
        }),
      ]);
  },
};
const assignOpen = vi.fn();
const AssignStub = {
  setup(_, { expose }) {
    expose({ open: assignOpen });
    return () => h('div');
  },
};

const ADMIN_SEAT = {
  role: 'administrator',
  customRoleId: null,
  permissions: [],
};

const buildStore = (
  roles = [],
  account = { features: { custom_roles: true } },
  seat = ADMIN_SEAT,
  agents = []
) => {
  const actions = {
    getCustomRole: vi.fn(),
    createCustomRole: vi.fn(async (_, payload) => ({ id: 9, ...payload })),
    updateCustomRole: vi.fn(),
  };
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => seat.role,
      getCurrentCustomRoleId: () => seat.customRoleId,
      getCurrentUser: () => ({
        id: 2,
        accounts: [
          {
            id: 1,
            custom_role_id: seat.customRoleId,
            permissions: seat.permissions,
          },
        ],
      }),
      'accounts/getAccount': () => () => (account ? { id: 1, ...account } : {}),
      'accounts/isFeatureEnabledonAccount': () => (_, feature) =>
        Boolean(account?.features?.[feature]),
      'customRole/getCustomRoles': () => roles,
      'customRole/getUIFlags': () => ({}),
      'agents/getAgents': () => agents,
    },
    actions: {
      'customRole/getCustomRole': actions.getCustomRole,
      'customRole/createCustomRole': actions.createCustomRole,
      'customRole/updateCustomRole': actions.updateCustomRole,
      'agents/get': vi.fn(),
    },
  });
  return { store, actions };
};

const mountEditor = async store => {
  const wrapper = mount(CustomRoleEditor, {
    global: {
      plugins: [store],
      mocks: {
        $t: (key, params) => (params?.name ? `${key}:${params.name}` : key),
      },
      stubs: { Dialog: DialogStub, AssignAgentsDialog: AssignStub },
    },
  });
  await flushPromises();
  return wrapper;
};

const buttonWith = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

beforeEach(() => {
  route.params = {};
  route.query = {};
  router.push.mockClear();
  router.replace.mockClear();
  assignOpen.mockClear();
  alerts.length = 0;
  dialogCalls.open = 0;
  dialogCalls.close = 0;
});

describe('CustomRoleEditor', () => {
  it('starts a new role on the profile step and fills it from the profile', async () => {
    const { store } = buildStore();
    const wrapper = await mountEditor(store);

    expect(wrapper.findComponent(ProfilePicker).exists()).toBe(true);
    wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'SUPERVISOR');
    await flushPromises();

    expect(wrapper.findComponent(ProfilePicker).exists()).toBe(false);
    expect(wrapper.text()).toContain('CUSTOM_ROLE.EDITOR.BASED_ON');
    expect(wrapper.find('input').element.value).toBe(
      'CUSTOM_ROLE.PROFILES.SUPERVISOR.NAME'
    );
  });

  it('creates the role and offers to assign agents', async () => {
    const { store, actions } = buildStore();
    const wrapper = await mountEditor(store);
    wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'AGENT');
    await flushPromises();

    await buttonWith(wrapper, 'CUSTOM_ROLE.ADD.SUBMIT').trigger('click');
    await flushPromises();

    const payload = actions.createCustomRole.mock.calls[0][1];
    expect(payload.permissions).toContain('conversation_participating_manage');
    expect(assignOpen).toHaveBeenCalledWith(expect.objectContaining({ id: 9 }));
    expect(dialogCalls.open).toBe(0);
  });

  it('refuses to save without a name', async () => {
    const { store, actions } = buildStore();
    const wrapper = await mountEditor(store);
    wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'BLANK');
    await flushPromises();

    await buttonWith(wrapper, 'CUSTOM_ROLE.ADD.SUBMIT').trigger('click');

    expect(actions.createCustomRole).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CUSTOM_ROLE.FORM.NAME.ERROR');
  });

  it('asks before turning on a sensitive option', async () => {
    route.params = { roleId: '3' };
    const { store, actions } = buildStore([
      { id: 3, name: 'Vendas', description: '', permissions: ['crm_view'] },
    ]);
    const wrapper = await mountEditor(store);

    await buttonWith(wrapper, 'CUSTOM_ROLE.MATRIX.GROUPS.CRM').trigger('click');
    await buttonWith(wrapper, 'CUSTOM_ROLE.EDITOR.FINE_TUNING').trigger(
      'click'
    );
    const exportSwitch = wrapper
      .findAll('li')
      .find(item => item.text().includes('CUSTOM_ROLE.PERMISSIONS.CRM_EXPORT'))
      .find('[role="switch"]');
    await exportSwitch.trigger('click');

    expect(dialogCalls.open).toBe(1);
    expect(exportSwitch.attributes('aria-checked')).toBe('false');

    await wrapper.find('.dialog-confirm').trigger('click');
    await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
    await flushPromises();

    expect(actions.updateCustomRole.mock.calls[0][1]).toEqual(
      expect.objectContaining({
        id: 3,
        permissions: expect.arrayContaining(['crm_view', 'crm_export']),
      })
    );
    expect(router.push).toHaveBeenCalledWith({ name: 'custom_roles_list' });
  });

  it('prefills a duplicated role and skips the profile step', async () => {
    route.query = { duplicate: '3' };
    const { store } = buildStore([
      { id: 3, name: 'SDR', description: 'x', permissions: ['crm_view'] },
    ]);
    const wrapper = await mountEditor(store);

    expect(wrapper.findComponent(ProfilePicker).exists()).toBe(false);
    expect(wrapper.find('input').element.value).toBe(
      'CUSTOM_ROLE.EDITOR.COPY_NAME:SDR'
    );
  });

  it('opens from a direct link before the account has loaded', async () => {
    const { store } = buildStore([], null);
    const wrapper = await mountEditor(store);

    expect(router.replace).not.toHaveBeenCalled();
    expect(wrapper.findComponent(ProfilePicker).exists()).toBe(true);
  });

  describe('fora do administrador (#1931)', () => {
    const builder = {
      role: 'agent',
      customRoleId: 5,
      permissions: ['custom_role_manage', 'crm_view', 'custom_role'],
    };
    const features = { features: { custom_roles: true } };

    it('does not open the role the person holds', async () => {
      route.params = { roleId: '5' };
      const { store } = buildStore(
        [{ id: 5, name: 'Minha', permissions: builder.permissions }],
        features,
        builder
      );
      await mountEditor(store);

      expect(router.replace).toHaveBeenCalledWith({
        name: 'custom_roles_list',
      });
    });

    it('does not open a role above the person reach', async () => {
      route.params = { roleId: '6' };
      const { store } = buildStore(
        [{ id: 6, name: 'Caixas', permissions: ['inbox_manage'] }],
        features,
        builder
      );
      await mountEditor(store);

      expect(router.replace).toHaveBeenCalledWith({
        name: 'custom_roles_list',
      });
    });

    it('keeps only reachable keys from a profile and skips assigning without people_manage', async () => {
      const { store, actions } = buildStore([], features, builder);
      const wrapper = await mountEditor(store);
      wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'FINANCE');
      await flushPromises();

      await buttonWith(wrapper, 'CUSTOM_ROLE.ADD.SUBMIT').trigger('click');
      await flushPromises();

      expect(actions.createCustomRole.mock.calls[0][1].permissions).toEqual([
        'crm_view',
      ]);
      expect(assignOpen).not.toHaveBeenCalled();
      expect(router.push).toHaveBeenCalledWith({ name: 'custom_roles_list' });
    });

    // #2115: a prévia usa o mesmo filtro, e o editor diz em que áreas o modelo ficou incompleto.
    it('passes its reach to the profile step and names the areas left out', async () => {
      const { store } = buildStore([], features, builder);
      const wrapper = await mountEditor(store);
      const reach = wrapper.findComponent(ProfilePicker).props('reach');

      expect(reach(['crm_view', 'financial_view', 'report_manage'])).toEqual([
        'crm_view',
      ]);

      wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'FINANCE');
      await flushPromises();

      const notice = wrapper.find('[role="status"]');
      expect(notice.text()).toContain('CUSTOM_ROLE.EDITOR.LEFT_OUT.TITLE');
      expect(notice.text()).toContain(
        'CUSTOM_ROLE.MATRIX.MODULES.REPORTS.NAME'
      );
      expect(notice.text()).toContain(
        'CUSTOM_ROLE.MATRIX.MODULES.FINANCE.NAME'
      );
      expect(notice.text()).toContain('CUSTOM_ROLE.MATRIX.MODULES.CRM.NAME');
    });
  });

  it('shows no left-out notice to an administrator', async () => {
    const { store } = buildStore();
    const wrapper = await mountEditor(store);
    wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'SALES_MANAGER');
    await flushPromises();

    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  // #2185: um nome por conta, sem diferenciar maiúsculas nem espaços.
  describe('nome repetido', () => {
    it('shows the error next to the name when another role has it', async () => {
      const { store, actions } = buildStore([
        { id: 3, name: 'Vendas', permissions: ['crm_view'] },
      ]);
      const wrapper = await mountEditor(store);
      wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'AGENT');
      await flushPromises();
      await wrapper.find('input').setValue('  vENDAS ');

      await buttonWith(wrapper, 'CUSTOM_ROLE.ADD.SUBMIT').trigger('click');
      await flushPromises();

      expect(actions.createCustomRole).not.toHaveBeenCalled();
      expect(wrapper.text()).toContain('CUSTOM_ROLE.FORM.NAME.TAKEN');
    });

    it('shows the error next to the name when the server refuses it', async () => {
      const { store, actions } = buildStore();
      actions.createCustomRole.mockRejectedValue(
        Object.assign(new Error('Name has already been taken'), {
          attributes: ['name'],
        })
      );
      const wrapper = await mountEditor(store);
      wrapper.findComponent(ProfilePicker).vm.$emit('choose', 'AGENT');
      await flushPromises();

      await buttonWith(wrapper, 'CUSTOM_ROLE.ADD.SUBMIT').trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('CUSTOM_ROLE.FORM.NAME.TAKEN');
      expect(alerts).not.toContain('Name has already been taken');
    });

    it('keeps the role own name when editing it', async () => {
      route.params = { roleId: '3' };
      const { store, actions } = buildStore([
        { id: 3, name: 'Vendas', permissions: ['crm_view'] },
      ]);
      const wrapper = await mountEditor(store);

      await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
      await flushPromises();

      expect(actions.updateCustomRole).toHaveBeenCalled();
    });

    // Como no servidor, o nome só é conferido quando muda: um repetido antigo continua mudando de chaves.
    it('lets an old duplicate save without renaming it', async () => {
      route.params = { roleId: '3' };
      const { store, actions } = buildStore([
        { id: 3, name: 'Vendas', permissions: ['crm_view'] },
        { id: 4, name: 'vendas', permissions: ['contact_view'] },
      ]);
      const wrapper = await mountEditor(store);

      await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
      await flushPromises();

      expect(actions.updateCustomRole).toHaveBeenCalled();
      expect(wrapper.text()).not.toContain('CUSTOM_ROLE.FORM.NAME.TAKEN');
    });
  });

  // #2185: quem tem a função perde acesso ao salvar; o administrador confirma antes.
  describe('perda de acesso', () => {
    const role = {
      id: 3,
      name: 'Vendas',
      permissions: ['crm_view', 'contact_view'],
    };
    const holder = { id: 7, name: 'Ana', role: 'agent', custom_role_id: 3 };
    const groupOf = (wrapper, key) =>
      wrapper
        .findAllComponents(PermissionGroup)
        .find(group => group.props('group').key === key);

    beforeEach(() => {
      route.params = { roleId: '3' };
    });

    it('lists the areas and saves only after the confirmation', async () => {
      const { store, actions } = buildStore([role], undefined, undefined, [
        holder,
      ]);
      const wrapper = await mountEditor(store);
      groupOf(wrapper, 'CRM').vm.$emit('clear');
      await flushPromises();

      await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
      await flushPromises();

      expect(dialogCalls.open).toBe(1);
      expect(actions.updateCustomRole).not.toHaveBeenCalled();
      const dialog = wrapper.find('.dialog-stub').text();
      expect(dialog).toContain('CUSTOM_ROLE.EDITOR.LOST_ACCESS.TITLE');
      expect(dialog).toContain('CUSTOM_ROLE.MATRIX.MODULES.CRM.NAME');
      expect(dialog).not.toContain('CUSTOM_ROLE.MATRIX.MODULES.CONTACTS.NAME');

      await wrapper.find('.dialog-confirm').trigger('click');
      await flushPromises();

      expect(actions.updateCustomRole.mock.calls[0][1].permissions).toEqual([
        'contact_view',
      ]);
    });

    it('does not ask when the role only gains keys', async () => {
      const { store, actions } = buildStore([role], undefined, undefined, [
        holder,
      ]);
      const wrapper = await mountEditor(store);
      const contacts = MODULES.find(module => module.key === 'CONTACTS');
      groupOf(wrapper, 'SERVICE').vm.$emit('selectLevel', contacts, 'manage');
      await flushPromises();

      await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
      await flushPromises();

      expect(dialogCalls.open).toBe(0);
      expect(actions.updateCustomRole).toHaveBeenCalled();
    });

    it('does not ask when nobody has the role', async () => {
      const { store, actions } = buildStore([role]);
      const wrapper = await mountEditor(store);
      groupOf(wrapper, 'CRM').vm.$emit('clear');
      await flushPromises();

      await buttonWith(wrapper, 'CUSTOM_ROLE.EDIT.SUBMIT').trigger('click');
      await flushPromises();

      expect(dialogCalls.open).toBe(0);
      expect(actions.updateCustomRole).toHaveBeenCalled();
    });
  });

  it('goes back to the list when the plan has no custom roles', async () => {
    const { store, actions } = buildStore([], { features: {} });
    await mountEditor(store);

    expect(router.replace).toHaveBeenCalledWith({ name: 'custom_roles_list' });
    expect(actions.getCustomRole).not.toHaveBeenCalled();
  });
});
