import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';

enableAutoUnmount(afterEach);

const listState = vi.hoisted(() => ({
  rows: null,
  status: null,
  error: null,
  isLoading: null,
  isStale: null,
  load: vi.fn(),
  retry: vi.fn(),
  updateStatus: vi.fn(),
  deleteDraft: vi.fn(),
}));

Object.assign(listState, {
  rows: ref([]),
  status: ref('success'),
  error: ref(null),
  isLoading: ref(false),
  isStale: ref(false),
});

vi.mock('../composables/useAgentsList.js', () => ({
  useAgentsList: () => listState,
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(true),
}));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

const loadPage = () => import('./AgentsListPage.vue');

const agent = {
  id: 'clara',
  name: 'Clara',
  agent_type: 'custom',
  actuation: 'external',
  state: { code: 'E5' },
  channels: [],
  stats: {
    week: { replies: 14, handoffs: 4 },
    month: { replies: 27, handoffs: 6 },
  },
};

describe('AgentsListPage', () => {
  beforeEach(() => {
    listState.rows.value = [];
    listState.status.value = 'success';
    listState.error.value = null;
    listState.isLoading.value = false;
    listState.isStale.value = false;
    vi.clearAllMocks();
  });

  it('carrega a lista real e mostra o resumo da projeção', async () => {
    listState.rows.value = [agent];
    const { default: AgentsListPage } = await loadPage();
    const wrapper = mount(AgentsListPage, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          AgentRow: {
            template: '<div data-agent-row>{{ agent.name }}</div>',
            props: ['agent'],
          },
          AgentsSummaryChips: {
            template: '<div data-summary />',
            props: ['agents'],
          },
        },
      },
    });
    await flushPromises();

    expect(listState.load).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-agent-row]').text()).toBe('Clara');
    expect(wrapper.find('[data-summary]').exists()).toBe(true);
    expect(wrapper.find('[data-pause-notice]').exists()).toBe(true);
  });

  it('só mostra vazio quando o GET terminou com payload vazio', async () => {
    const { default: AgentsListPage } = await loadPage();
    const wrapper = mount(AgentsListPage, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          AgentsEmptyHero: {
            template: '<div data-empty />',
            props: ['canManage'],
          },
        },
      },
    });
    await flushPromises();

    expect(wrapper.find('[data-empty]').exists()).toBe(true);
  });

  it('mantém os cartões e mostra alerta quando a releitura fica desatualizada', async () => {
    listState.rows.value = [agent];
    listState.error.value = new Error('offline');
    listState.status.value = 'error';
    listState.isStale.value = true;
    const { default: AgentsListPage } = await loadPage();
    const wrapper = mount(AgentsListPage, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          AgentRow: {
            template: '<div data-agent-row>{{ agent.name }}</div>',
            props: ['agent'],
          },
          NoticeBanner: { template: '<div role="alert"><slot /></div>' },
        },
      },
    });

    expect(wrapper.find('[data-agent-row]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });
});
