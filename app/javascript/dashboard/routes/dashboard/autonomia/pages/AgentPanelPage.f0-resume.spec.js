import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import AgentPanelPage from './AgentPanelPage.vue';

const currentAccount = ref({
  id: 9,
  autonomia_agents_redesign: true,
  autonomia_agents_redesign_enabled: true,
});

const mocks = vi.hoisted(() => ({
  alert: vi.fn(),
  canManage: { value: true },
  order: [],
  router: {
    push: vi.fn(),
    replace: vi.fn(),
  },
  store: {
    getters: {
      'autonomiaAgents/getRecord': vi.fn(),
    },
    dispatch: vi.fn(),
  },
  getterValues: {
    'autonomiaAgents/getUIFlags': {
      value: { fetchingItem: false, updatingItem: false },
    },
    getCurrentUser: { value: { type: 'User' } },
    getCurrentCustomRoleId: { value: null },
    getCurrentAccountId: { value: 9 },
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => mocks.store,
  useMapGetter: key => mocks.getterValues[key],
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount }),
}));

vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => mocks.canManage,
}));

vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => mocks.router,
}));

const PanelTuneStub = {
  name: 'PanelTune',
  props: ['agent', 'agentId'],
  setup() {
    mocks.order.push('panel-mounted');
    return () => null;
  },
};

const agent = (overrides = {}) => ({
  id: 7,
  name: 'Clara',
  agent_type: 'support',
  mode: 'guided',
  status: 'draft',
  actuation: 'external',
  state: { code: 'E2', continuation: 'tell' },
  ...overrides,
});

const mountPage = ({
  currentAgent = agent(),
  tab = 'tune',
  manage = true,
} = {}) => {
  mocks.canManage.value = manage;
  mocks.store.getters['autonomiaAgents/getRecord'].mockReturnValue(
    currentAgent
  );
  return mount(AgentPanelPage, {
    props: { agentId: currentAgent.id, tab },
    global: {
      stubs: {
        PanelTune: PanelTuneStub,
        PanelTest: true,
        PanelKnowledge: true,
        PanelChannels: true,
        PanelPerformance: true,
        PanelPublish: true,
        PanelTools: true,
        Avatar: true,
        Spinner: true,
      },
    },
  });
};

const navigationCalls = () =>
  [...mocks.router.push.mock.calls, ...mocks.router.replace.mock.calls].map(
    ([target]) => target
  );

describe('F0: retomada da entrada do painel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    currentAccount.value = {
      id: 9,
      autonomia_agents_redesign: true,
      autonomia_agents_redesign_enabled: true,
    };
    mocks.order.length = 0;
    mocks.canManage.value = true;
    mocks.store.getters['autonomiaAgents/getRecord'].mockReturnValue(agent());
    mocks.store.dispatch.mockImplementation(action => {
      mocks.order.push(action);
      return Promise.resolve();
    });
  });

  it('hidrata a última thread nested antes de montar PanelTune para editor guiado', async () => {
    let resolveResume;
    const resume = new Promise(resolve => {
      resolveResume = resolve;
    });
    mocks.store.dispatch.mockImplementation(action => {
      mocks.order.push(action);
      if (action === 'autonomiaBuildThreads/resume') return resume;
      return Promise.resolve();
    });

    mountPage({
      currentAgent: agent({ state: { code: 'E3', continuation: 'test' } }),
    });
    await Promise.resolve();

    expect(mocks.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      { agentId: 7 }
    );
    expect(mocks.order).not.toContain('panel-mounted');

    resolveResume({ id: 88, agent_id: 7, status: 'ready', messages: [] });
    await flushPromises();

    expect(mocks.order.indexOf('autonomiaBuildThreads/resume')).toBeLessThan(
      mocks.order.indexOf('panel-mounted')
    );
  });

  it('não hidrata BE-05 nem cria thread para E2m manual', async () => {
    mountPage({
      currentAgent: agent({ mode: 'manual', state: { code: 'E2m' } }),
    });
    await flushPromises();

    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      expect.anything()
    );
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
  });

  it.each([
    ['E1', 'tell'],
    ['E4', 'live'],
  ])(
    'mantém viewer %s em leitura e não escreve no store de threads',
    async (code, continuation) => {
      mountPage({
        currentAgent: agent({ state: { code, continuation } }),
        tab: 'performance',
        manage: false,
      });
      await flushPromises();

      expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/resume',
        expect.anything()
      );
      expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/start',
        expect.anything()
      );
      expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/send',
        expect.anything()
      );
    }
  );

  it.each([401, 404, 422])(
    'preserva o agente e sai com aviso localizado quando resume falha com %s',
    async status => {
      mocks.store.dispatch.mockImplementation(action => {
        mocks.order.push(action);
        if (action === 'autonomiaBuildThreads/resume') {
          return Promise.reject(
            Object.assign(new Error('resume failed'), { response: { status } })
          );
        }
        return Promise.resolve();
      });
      const currentAgent = agent({
        state: { code: 'E2', continuation: 'tell' },
      });

      mountPage({ currentAgent });
      await flushPromises();

      expect(mocks.store.getters['autonomiaAgents/getRecord']()).toEqual(
        currentAgent
      );
      expect(mocks.alert).toHaveBeenCalledWith(
        expect.stringMatching(/^AGENTS\./)
      );
      expect(
        navigationCalls().some(target =>
          ['autonomia_agents_index', 'autonomia_agent_panel'].includes(
            target?.name
          )
        )
      ).toBe(true);
      expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/start',
        expect.anything()
      );
    }
  );
});
