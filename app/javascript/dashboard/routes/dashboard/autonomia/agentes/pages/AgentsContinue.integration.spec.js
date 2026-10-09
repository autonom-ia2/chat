import { createMemoryHistory, createRouter, RouterView } from 'vue-router';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

import AgentsListPage from './AgentsListPage.vue';
import AgentPanelPage from '../../pages/AgentPanelPage.vue';
import AgentCreationPage from './AgentCreationPage.vue';

enableAutoUnmount(afterEach);

const harness = vi.hoisted(() => {
  const state = {
    agent: null,
    resumeError: null,
    dispatches: [],
    alert: vi.fn(),
    canManage: null,
    currentAccount: null,
    getters: {},
    list: {},
    store: {
      getters: {},
      dispatch: vi.fn(),
      commit: vi.fn(),
    },
  };

  state.store.getters['autonomiaAgents/getRecord'] = vi.fn(() => state.agent);

  return state;
});

vi.mock('../composables/useAgentsList.js', () => ({
  useAgentsList: () => harness.list,
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => harness.store,
  useMapGetter: key => harness.getters[key] || { value: null },
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: harness.currentAccount }),
}));

vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => harness.canManage,
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => harness.alert(...args),
}));

vi.mock('dashboard/api/autonomia/sources', () => ({
  default: {
    reusable: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const agentFixture = ({ code = 'E2', mode = 'guided', id = 7 } = {}) => ({
  id,
  name: 'Clara',
  avatar_url: null,
  agent_type: 'custom',
  actuation: 'external',
  mode,
  status: 'draft',
  voice: 'feminina',
  state: { code, continuation: 'tell', retention_hours: 24 },
  channels: [],
  stats: {
    week: { replies: 0, handoffs: 0 },
    month: { replies: 0, handoffs: 0 },
  },
  config: {},
});

const routeRecords = [
  {
    path: '/accounts/:accountId/agents',
    name: 'autonomia_agents_index',
    component: AgentsListPage,
  },
  {
    path: '/accounts/:accountId/agents/:agentId/build/:step',
    name: 'autonomia_agent_build',
    component: AgentCreationPage,
    props: route => ({
      agentId: route.params.agentId,
      step: route.params.step,
    }),
  },
  {
    path: '/accounts/:accountId/agents/:agentId/legacy/:tab',
    name: 'autonomia_agent_panel_legacy',
    component: AgentPanelPage,
    props: route => ({
      agentId: route.params.agentId,
      tab: route.params.tab || 'test',
    }),
  },
  {
    path: '/accounts/:accountId/agents/:agentId/:tab?',
    name: 'autonomia_agent_panel',
    component: AgentPanelPage,
    props: route => ({
      agentId: route.params.agentId,
      tab: route.params.tab || 'performance',
    }),
  },
];

const panelStubs = {
  PanelTune: {
    name: 'PanelTune',
    template: '<section data-panel="tune" />',
  },
  PanelTest: {
    name: 'PanelTest',
    template: '<section data-panel="test" />',
  },
  PanelPublish: {
    name: 'PanelPublish',
    template: '<section data-panel="publish" />',
  },
  PanelKnowledge: true,
  PanelChannels: true,
  PanelPerformance: {
    name: 'PanelPerformance',
    template: '<section data-panel="performance" />',
  },
  PanelTools: true,
  Avatar: true,
  Spinner: true,
  AgentAvatar: true,
  AgentStatusPill: true,
  ConfirmDialog: {
    template: '<div data-confirm-dialog />',
    methods: { open() {}, close() {} },
  },
};

const creationStubs = {
  AgentSteps: {
    template: '<nav data-creation-steps />',
  },
  AgentBuildChoosePage: {
    template: '<section data-creation-step="choice" />',
  },
  AgentBuildTellPage: {
    props: ['agentId'],
    template: '<section data-creation-step="tell" :data-agent-id="agentId" />',
  },
  AgentTestPhone: {
    props: ['agentId'],
    template: '<section data-creation-step="test" :data-agent-id="agentId" />',
  },
  AgentBuildGoLivePage: {
    props: ['agent'],
    template:
      '<section data-creation-step="live" :data-agent-id="agent?.id" />',
  },
  AgentReadyPage: {
    template: '<section data-creation-step="ready" />',
  },
};

const mountAtList = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: routeRecords,
  });
  await router.push({
    name: 'autonomia_agents_index',
    params: { accountId: '9' },
  });
  await router.isReady();

  const wrapper = mount(RouterView, {
    global: {
      plugins: [router],
      stubs: { ...panelStubs, ...creationStubs },
    },
  });
  await flushPromises();

  return { router, wrapper };
};

describe('AgentsListPage: continuação pela rota real', () => {
  beforeEach(() => {
    harness.agent = null;
    harness.resumeError = null;
    harness.dispatches = [];
    harness.alert.mockReset();
    harness.canManage = ref(true);
    harness.currentAccount = ref({
      id: 9,
      autonomia_agents_enabled: true,
      autonomia_agents_redesign: true,
      autonomia_agents_redesign_enabled: true,
    });
    harness.getters = {
      'autonomiaAgents/getUIFlags': ref({
        fetchingItem: false,
        updatingItem: false,
      }),
      getCurrentUser: ref({ type: 'User' }),
      getCurrentAccountId: ref(9),
    };
    harness.list = {
      rows: ref([]),
      status: ref('success'),
      error: ref(null),
      isLoading: ref(false),
      isStale: ref(false),
      load: vi.fn(),
      retry: vi.fn(),
      updateStatus: vi.fn(),
      deleteDraft: vi.fn(),
    };
    harness.store.dispatch.mockReset();
    harness.store.dispatch.mockImplementation((type, payload) => {
      harness.dispatches.push({ type, payload });
      if (type === 'autonomiaBuildThreads/resume' && harness.resumeError) {
        const error = harness.resumeError;
        harness.resumeError = null;
        return Promise.reject(error);
      }
      if (type === 'autonomiaBuildThreads/resume') {
        return Promise.resolve({
          id: 88,
          agent_id: harness.agent.id,
          status: 'ready',
          messages: [],
        });
      }
      return Promise.resolve();
    });
  });

  it.each(['E1', 'E2'])(
    'leva %s para build/tell com uma única hidratação e sem start',
    async code => {
      const agent = agentFixture({ code });
      harness.agent = agent;
      harness.list.rows.value = [agent];

      const { router, wrapper } = await mountAtList();
      await wrapper.find('[data-action="continue"]').trigger('click');
      await flushPromises();

      expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
      expect(router.currentRoute.value.params).toMatchObject({
        accountId: '9',
        agentId: '7',
        step: 'tell',
      });
      expect(
        harness.dispatches.filter(
          ({ type }) => type === 'autonomiaBuildThreads/resume'
        )
      ).toEqual([
        { type: 'autonomiaBuildThreads/resume', payload: { agentId: 7 } },
      ]);
      expect(harness.dispatches.map(({ type }) => type)).not.toContain(
        'autonomiaBuildThreads/start'
      );
      expect(wrapper.find('[data-creation-step="tell"]').exists()).toBe(true);
      expect(wrapper.find('[data-agent-id="7"]').exists()).toBe(true);
    }
  );

  it.each([
    ['E3', 'test'],
    ['E4', 'live'],
  ])('leva %s para %s sem retomar nem criar uma thread', async (code, step) => {
    const agent = agentFixture({ code });
    harness.agent = agent;
    harness.list.rows.value = [agent];

    const { router, wrapper } = await mountAtList();
    await wrapper.find('[data-action="continue"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params).toMatchObject({
      accountId: '9',
      agentId: '7',
      step,
    });
    expect(harness.dispatches.map(({ type }) => type)).not.toEqual(
      expect.arrayContaining([
        'autonomiaBuildThreads/resume',
        'autonomiaBuildThreads/start',
      ])
    );
    if (step === 'test') {
      expect(harness.dispatches.map(({ type }) => type)).not.toContain(
        'autonomiaChannels/fetch'
      );
    }
    expect(wrapper.find(`[data-creation-step="${step}"]`).exists()).toBe(true);
  });

  it.each([401, 404])(
    'mantém Conte no contexto e oferece retry quando a retomada falha com %s',
    async status => {
      const agent = agentFixture({ code: 'E2' });
      harness.agent = agent;
      harness.list.rows.value = [agent];
      harness.resumeError = Object.assign(new Error('resume failed'), {
        response: { status },
      });

      const { router, wrapper } = await mountAtList();
      await wrapper.find('[data-action="continue"]').trigger('click');
      await flushPromises();
      await flushPromises();

      expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
      expect(router.currentRoute.value.params).toMatchObject({
        accountId: '9',
        agentId: '7',
        step: 'tell',
      });
      expect(wrapper.find('[data-creation-step="tell"]').exists()).toBe(true);
      expect(wrapper.find('[data-agent-id="7"]').exists()).toBe(true);
      expect(
        wrapper.find('[data-action="creation-entry-retry"]').exists()
      ).toBe(true);
      expect(harness.alert).toHaveBeenCalledWith(
        'AGENTS.CREATION.errors.resume'
      );
      expect(
        harness.dispatches.filter(
          ({ type }) => type === 'autonomiaBuildThreads/resume'
        )
      ).toHaveLength(1);
      expect(harness.dispatches.map(({ type }) => type)).not.toContain(
        'autonomiaBuildThreads/start'
      );
      await wrapper
        .find('[data-action="creation-entry-retry"]')
        .trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
      expect(
        harness.dispatches.filter(
          ({ type }) => type === 'autonomiaBuildThreads/resume'
        )
      ).toHaveLength(2);
    }
  );

  it('leva E2m para o painel legado sem retomar nem criar thread', async () => {
    const agent = agentFixture({ code: 'E2m', mode: 'manual' });
    harness.agent = agent;
    harness.list.rows.value = [agent];

    const { router, wrapper } = await mountAtList();
    await wrapper.find('[data-action="continue"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.name).toBe('autonomia_agent_panel_legacy');
    expect(router.currentRoute.value.params.tab).toBe('tune');
    expect(harness.dispatches.map(({ type }) => type)).not.toEqual(
      expect.arrayContaining([
        'autonomiaBuildThreads/resume',
        'autonomiaBuildThreads/start',
      ])
    );
    expect(wrapper.find('[data-panel="tune"]').exists()).toBe(true);
  });

  it('deixa viewer abrir E1 sem Continuar e sem escrita de thread', async () => {
    const agent = agentFixture({ code: 'E1' });
    harness.agent = agent;
    harness.canManage.value = false;
    harness.list.rows.value = [agent];

    const { router, wrapper } = await mountAtList();
    expect(wrapper.find('[data-action="continue"]').exists()).toBe(false);
    await wrapper.find('[data-action="open"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.name).toBe('autonomia_agent_panel');
    expect(harness.dispatches.map(({ type }) => type)).not.toEqual(
      expect.arrayContaining([
        'autonomiaBuildThreads/resume',
        'autonomiaBuildThreads/start',
      ])
    );
    expect(wrapper.find('[data-panel="performance"]').exists()).toBe(true);
  });
});
