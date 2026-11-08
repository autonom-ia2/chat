import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { h } from 'vue';
import Index from '../Index.vue';

// #2185: na lista, excluir uma função com gente abre a pergunta do destino; sem gente, a confirmação de sempre.
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const moveOpen = vi.fn();
let moveDialog = null;
const DeleteRoleDialogStub = {
  emits: ['confirm'],
  setup(_, { expose, emit }) {
    moveDialog = { confirm: payload => emit('confirm', payload) };
    expose({ open: moveOpen });
    return () => h('div');
  },
};
const CardStub = {
  props: { role: { type: Object, required: true } },
  emits: ['delete'],
  setup(props, { emit }) {
    return () =>
      h('button', {
        class: `delete-${props.role.id}`,
        onClick: () => emit('delete', props.role),
      });
  },
};
const LayoutStub = {
  setup(_, { slots }) {
    return () => h('div', [slots.body?.(), slots.default?.()]);
  },
};
const DeleteModalStub = {
  props: {
    show: { type: Boolean, default: false },
    onConfirm: { type: Function, default: () => {} },
  },
  setup(props) {
    return () =>
      h('button', {
        class: 'delete-modal',
        'data-show': props.show,
        onClick: () => props.onConfirm(),
      });
  },
};

const ROLES = [
  { id: 1, name: 'Vendas', permissions: ['crm_view'] },
  { id: 2, name: 'Suporte', permissions: ['conversation_view'] },
];
const AGENTS = [{ id: 7, name: 'Ana', role: 'agent', custom_role_id: 1 }];

const buildStore = () => {
  const actions = {
    getCustomRole: vi.fn(),
    deleteCustomRole: vi.fn(),
    getAgents: vi.fn(),
  };
  const store = createStore({
    state: { agents: AGENTS },
    mutations: {
      setAgents(state, agents) {
        state.agents = agents;
      },
    },
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'administrator',
      getCurrentCustomRoleId: () => null,
      getCurrentUser: () => ({ id: 2, accounts: [{ id: 1, permissions: [] }] }),
      'accounts/isFeatureEnabledonAccount': () => () => true,
      'customRole/getCustomRoles': () => ROLES,
      'customRole/getUIFlags': () => ({}),
      'agents/getAgents': state => state.agents,
    },
    actions: {
      'customRole/getCustomRole': actions.getCustomRole,
      'customRole/deleteCustomRole': actions.deleteCustomRole,
      'agents/get': actions.getAgents,
    },
  });
  return { store, actions };
};

const mountIndex = async store => {
  const wrapper = mount(Index, {
    global: {
      plugins: [store],
      stubs: {
        SettingsLayout: LayoutStub,
        BaseSettingsHeader: true,
        CustomRolePaywall: true,
        CustomRoleCard: CardStub,
        DeleteRoleDialog: DeleteRoleDialogStub,
        'woot-delete-modal': DeleteModalStub,
      },
      mocks: { $t: key => key },
    },
  });
  await flushPromises();
  return wrapper;
};

beforeEach(() => moveOpen.mockClear());

describe('custom roles list: delete', () => {
  it('asks where the people go and sends the choice', async () => {
    const { store, actions } = buildStore();
    const wrapper = await mountIndex(store);
    actions.getAgents.mockClear();

    await wrapper.find('.delete-1').trigger('click');

    expect(moveOpen).toHaveBeenCalledWith(ROLES[0], 1);
    expect(wrapper.find('.delete-modal').attributes('data-show')).toBe('false');

    moveDialog.confirm({ role: ROLES[0], destinationRoleId: 2 });
    await flushPromises();

    expect(actions.deleteCustomRole.mock.calls[0][1]).toEqual({
      id: 1,
      destinationRoleId: 2,
    });
    expect(actions.getAgents).toHaveBeenCalled();
  });

  it('keeps the plain confirmation for a role nobody has', async () => {
    const { store } = buildStore();
    const wrapper = await mountIndex(store);

    await wrapper.find('.delete-2').trigger('click');

    expect(moveOpen).not.toHaveBeenCalled();
    expect(wrapper.find('.delete-modal').attributes('data-show')).toBe('true');
  });

  // A lista de agentes estava velha: o servidor acha gente na função e a tela faz a pergunta do destino.
  it('asks where the people go when the server finds people in the role', async () => {
    const { store, actions } = buildStore();
    actions.deleteCustomRole.mockRejectedValue(
      Object.assign(new Error('This role has people.'), {
        code: 'destination_required',
      })
    );
    const wrapper = await mountIndex(store);
    actions.getAgents.mockImplementation(({ commit }) =>
      commit('setAgents', [
        ...AGENTS,
        { id: 8, name: 'Bia', role: 'agent', custom_role_id: 2 },
      ])
    );

    await wrapper.find('.delete-2').trigger('click');
    await wrapper.find('.delete-modal').trigger('click');
    await flushPromises();

    expect(moveOpen).toHaveBeenCalledWith(ROLES[1], 1);
  });
});
