import { createMemoryHistory, createRouter } from 'vue-router';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import enAgents from 'dashboard/i18n/locale/en/agents.json';
import ptAgents from 'dashboard/i18n/locale/pt_BR/agents.json';

const harness = vi.hoisted(() => ({
  alert: vi.fn(),
  canManage: { value: true },
  currentAccount: { value: null },
  getters: {},
  store: {
    getters: {},
    dispatch: vi.fn(() => Promise.resolve()),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => harness.store,
  useMapGetter: key => harness.getters[key] || { value: null },
  useFunctionGetter: key => harness.getters[key] || { value: () => null },
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

const loadPage = () => import('./AgentCreationPage.vue');

const agent = {
  id: 42,
  name: 'Clara',
  greeting: 'Oi! Como posso ajudar?',
  agent_type: 'support',
  actuation: 'external',
  status: 'draft',
  enabled: false,
  state: { code: 'E3', continuation: 'test' },
  config: { name: 'Clara', greeting: 'Oi! Como posso ajudar?' },
};

const childStubs = {
  AgentBuildChoosePage: {
    template: '<section data-child="choice" />',
  },
  AgentBuildTellPage: {
    emits: ['leave'],
    template:
      '<section data-child="tell"><button type="button" data-action="creation-save-exit" @click="$emit(\'leave\')">leave</button></section>',
  },
  AgentTestPhone: {
    props: ['testValid'],
    emits: ['savePresentation', 'continue', 'leave', 'back'],
    template: `<section data-child="test">
      <button type="button" data-action="save-presentation" @click="$emit('savePresentation', { name: 'Clara nova', greeting: 'Olá, posso ajudar?' })">save</button>
      <button type="button" data-action="creation-continue" :disabled="!testValid" @click="$emit('continue')">continue</button>
    </section>`,
  },
  AgentBuildGoLivePage: {
    emits: ['publish'],
    template: '<section data-child="live" />',
  },
  AgentReadyPage: {
    template: '<section data-child="ready" />',
  },
};

const makeRouter = async step => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/accounts/:accountId/agents',
        name: 'autonomia_agents_index',
        component: { template: '<div data-route="agents" />' },
      },
      {
        path: '/accounts/:accountId/agents/:agentId/build/:step',
        name: 'autonomia_agent_build',
        component: { template: '<div data-route="build" />' },
      },
    ],
  });
  await router.push({
    name: 'autonomia_agent_build',
    params: { accountId: '85', agentId: '42', step },
  });
  await router.isReady();
  return router;
};

const mountPage = async (props, locale = 'pt_BR') => {
  const { default: AgentCreationPage } = await loadPage();
  const router = await makeRouter(props.step || 'choice');
  const i18n = createI18n({
    legacy: false,
    locale,
    messages: { en: enAgents, pt_BR: ptAgents },
  });
  const wrapper = mount(AgentCreationPage, {
    props,
    global: {
      plugins: [router, i18n],
      stubs: childStubs,
    },
  });
  await flushPromises();
  return { router, wrapper };
};

const resetHarness = () => {
  const account = {
    id: 85,
    autonomia_agents_enabled: true,
    autonomia_agents_redesign: true,
    autonomia_agents_redesign_enabled: true,
  };
  const values = {
    'autonomiaAgents/getRecord': ref(agent),
    'autonomiaBuildThreads/getThread': ref({ id: 91, agent_id: 42 }),
    'autonomiaBuildThreads/getMessages': ref([]),
    'autonomiaBuildThreads/getStatus': ref('ready'),
    'autonomiaBuildThreads/getPhase': ref('reviewing'),
    'autonomiaBuildThreads/getError': ref(null),
    'autonomiaBuildThreads/getThreadState': ref({}),
    'autonomiaBuildThreads/getAgent': ref(agent),
    'autonomiaBuildThreads/getUIFlags': ref({
      creating: false,
      sending: false,
      fetching: false,
    }),
    'autonomiaChannels/getEligible': ref([
      { id: 8, name: 'WhatsApp comercial' },
    ]),
    'autonomiaChannels/getUIFlags': ref({}),
    'autonomiaSources/getSources': ref([]),
    'autonomiaSources/getUIFlags': ref({}),
  };
  harness.currentAccount.value = account;
  harness.getters = values;
  harness.store.getters = Object.fromEntries(
    Object.entries(values).map(([key, value]) => [key, value.value])
  );
  harness.store.dispatch.mockReset();
  harness.store.dispatch.mockResolvedValue({
    id: 91,
    status: 'ready',
    agent_id: 42,
  });
  harness.alert.mockReset();
};

describe('AgentCreationPage — Escolha, Conte, Teste, Ligue e Pronto', () => {
  beforeEach(() => {
    resetHarness();
  });

  it('expõe entrada controlada por agente e pelas cinco telas da jornada', async () => {
    const { default: AgentCreationPage } = await loadPage();

    expect(AgentCreationPage.props).toHaveProperty('agentId');
    expect(AgentCreationPage.props).toHaveProperty('step');
    expect(AgentCreationPage.props.step.validator('choice')).toBe(true);
    expect(AgentCreationPage.props.step.validator('tell')).toBe(true);
    expect(AgentCreationPage.props.step.validator('test')).toBe(true);
    expect(AgentCreationPage.props.step.validator('live')).toBe(true);
    expect(AgentCreationPage.props.step.validator('ready')).toBe(true);

    const { wrapper } = await mountPage({ step: 'choice' });
    wrapper.unmount();
  });

  it.each(['en', 'pt_BR'])(
    'mostra a barra de quatro etapas em %s e trata Pronto como conclusão',
    async locale => {
      const { wrapper } = await mountPage({ step: 'tell' }, locale);

      expect(wrapper.findAll('nav button')).toHaveLength(4);
      expect(wrapper.find('[data-step="1"]').exists()).toBe(true);
      expect(wrapper.find('[data-step="2"]').exists()).toBe(true);
      expect(wrapper.find('[data-step="3"]').exists()).toBe(true);
      expect(wrapper.find('[data-step="4"]').exists()).toBe(true);
      expect(wrapper.find('[data-step="5"]').exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it('libera Ligue só após teste válido e invalida o teste ao mudar a apresentação', async () => {
    const { wrapper } = await mountPage({ agentId: 42, step: 'test' });
    const continueButton = wrapper.get('[data-action="creation-continue"]');

    expect(continueButton.attributes('disabled')).toBeDefined();

    harness.getters['autonomiaBuildThreads/getAgent'].value = {
      ...agent,
      state: { code: 'E4', continuation: 'live' },
    };
    await flushPromises();
    expect(continueButton.attributes('disabled')).toBeUndefined();

    await wrapper.get('[data-action="save-presentation"]').trigger('click');
    await flushPromises();
    expect(harness.store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/update',
      {
        id: 42,
        name: 'Clara nova',
        greeting: 'Olá, posso ajudar?',
      }
    );
    expect(continueButton.attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('carrega as caixas antes de liberar a resposta atrasada do agente', async () => {
    let resolveAgent;
    const pendingAgent = new Promise(resolve => {
      resolveAgent = resolve;
    });
    harness.store.dispatch.mockImplementation(action => {
      if (action === 'autonomiaAgents/show') return pendingAgent;
      return Promise.resolve({ id: 91, agent_id: 42, status: 'ready' });
    });

    const { wrapper } = await mountPage({ agentId: 42, step: 'live' });
    expect(harness.store.dispatch).toHaveBeenCalledWith(
      'autonomiaChannels/fetch',
      { agentId: 42 }
    );
    resolveAgent(agent);
    await flushPromises();
    expect(
      harness.store.dispatch.mock.calls.filter(
        ([action]) => action === 'autonomiaChannels/fetch'
      )
    ).toHaveLength(1);
    wrapper.unmount();
  });

  it('retoma a thread antes de montar Conte e sai preservando o rascunho', async () => {
    const { router, wrapper } = await mountPage({
      agentId: 42,
      step: 'tell',
    });

    expect(harness.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      { agentId: 42 }
    );
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );

    const navigation = new Promise(resolve => {
      router.afterEach(resolve);
    });
    await wrapper.get('[data-action="creation-save-exit"]').trigger('click');
    await navigation;
    expect(router.currentRoute.value.name).toBe('autonomia_agents_index');
    wrapper.unmount();
  });

  it('leva API/Guia com instrução direto ao Teste sem criar ou retomar thread', async () => {
    const { router, wrapper } = await mountPage({
      agentId: 42,
      step: 'test',
    });

    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params.step).toBe('test');
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      expect.anything()
    );
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    wrapper.unmount();
  });

  it('mantém Conte na tela quando a retomada legítima responde 404 e oferece retry', async () => {
    const resumeError = new Error('thread inexistente');
    resumeError.response = { status: 404 };
    harness.store.dispatch.mockImplementation(action => {
      if (action === 'autonomiaAgents/show') return Promise.resolve(agent);
      if (action === 'autonomiaBuildThreads/resume')
        return Promise.reject(resumeError);
      return Promise.resolve({ id: 91, agent_id: 42, status: 'ready' });
    });

    const { router, wrapper } = await mountPage({
      agentId: 42,
      step: 'tell',
    });

    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params.step).toBe('tell');
    expect(wrapper.get('[data-action="creation-entry-retry"]').exists()).toBe(
      true
    );
    expect(
      wrapper
        .get('[data-testid="creation-entry-error"]')
        .attributes('data-error-status')
    ).toBe('404');
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    wrapper.unmount();
  });

  it('não deixa falha de canais tirar o Teste da jornada', async () => {
    harness.store.dispatch.mockImplementation(action => {
      if (action === 'autonomiaAgents/show') return Promise.resolve(agent);
      if (action === 'autonomiaChannels/fetch')
        return Promise.reject(new Error('canais indisponíveis'));
      return Promise.resolve({ id: 91, agent_id: 42, status: 'ready' });
    });

    const { router, wrapper } = await mountPage({
      agentId: 42,
      step: 'test',
    });

    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params.step).toBe('test');
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaChannels/fetch',
      expect.anything()
    );
    wrapper.unmount();
  });

  it('mantém Ligue no contexto e refaz somente a leitura de canais após falha transitória', async () => {
    let channelAttempt = 0;
    const channelsError = new Error('canais indisponíveis');
    channelsError.response = { status: 503 };
    harness.store.dispatch.mockImplementation(action => {
      if (action === 'autonomiaAgents/show') return Promise.resolve(agent);
      if (action === 'autonomiaChannels/fetch') {
        channelAttempt += 1;
        return channelAttempt === 1
          ? Promise.reject(channelsError)
          : Promise.resolve({ payload: [], eligible_inboxes: [] });
      }
      return Promise.resolve({ id: 91, agent_id: 42, status: 'ready' });
    });

    const { router, wrapper } = await mountPage({
      agentId: 42,
      step: 'live',
    });

    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params.step).toBe('live');
    expect(wrapper.get('[data-action="creation-entry-retry"]').exists()).toBe(
      true
    );
    await wrapper.get('[data-action="creation-entry-retry"]').trigger('click');
    await flushPromises();

    expect(channelAttempt).toBe(2);
    expect(router.currentRoute.value.name).toBe('autonomia_agent_build');
    expect(router.currentRoute.value.params.step).toBe('live');
    expect(harness.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    wrapper.unmount();
  });
});
