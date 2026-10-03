import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { h } from 'vue';
import CustomRoleEditor from '../CustomRoleEditor.vue';
import ProfilePicker from '../component/ProfilePicker.vue';

const route = { params: {}, query: {} };
const router = { push: vi.fn(), replace: vi.fn() };
const alerts = [];

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => router,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params?.name ? `${key}:${params.name}` : key),
  }),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));

const dialogCalls = { open: 0, close: 0 };
// Stubs como objetos simples: são dublês do teste, não componentes do arquivo.
const DialogStub = {
  props: { title: { type: String, default: '' } },
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

const buildStore = (roles = []) => {
  const actions = {
    getCustomRole: vi.fn(),
    createCustomRole: vi.fn(async (_, payload) => ({ id: 9, ...payload })),
    updateCustomRole: vi.fn(),
  };
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => () => true,
      'customRole/getCustomRoles': () => roles,
      'customRole/getUIFlags': () => ({}),
      'agents/getAgents': () => [],
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
});
