import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgentPanelPage from './AgentPanelPage.vue';

const context = vi.hoisted(() => ({
  dispatch: vi.fn(),
  push: vi.fn(),
  replace: vi.fn(),
  record: null,
  canManage: null,
  user: null,
}));
context.record = ref(null);
context.canManage = ref(true);
context.user = ref({
  type: 'User',
  accounts: [{ id: 7, role: 'administrator' }],
});
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => context.canManage,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({ id: 7 }) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: context.dispatch,
    getters: { 'autonomiaAgents/getRecord': () => context.record.value },
  }),
  useMapGetter: key =>
    key === 'getCurrentUser' ? context.user : ref({ updatingItem: false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: context.push, replace: context.replace }),
}));
withFullI18n();
enableAutoUnmount(afterEach);

const shell = {
  name: 'AgentPanelShell',
  props: ['visibleTabs', 'actionRoute'],
  template: '<div><slot /></div>',
};
const mountPage = props =>
  mount(AgentPanelPage, {
    props: { agentId: 42, ...props },
    global: {
      stubs: {
        AgentPanelShell: shell,
        ConfirmDialog: true,
        Spinner: true,
        PanelWhereServes: true,
        PanelKnows: true,
        PanelAgentTest: true,
        PanelToolsV2: true,
        PanelSettings: true,
        PanelHowItsGoing: true,
        PanelQuoteKnowledge: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  context.dispatch.mockResolvedValue(undefined);
  context.canManage.value = true;
  context.user.value = {
    type: 'User',
    accounts: [{ id: 7, role: 'administrator' }],
  };
  context.record.value = {
    id: 42,
    name: 'Clara',
    agent_type: 'custom',
    actuation: 'external',
    mode: 'guided',
    state: { code: 'E5' },
  };
});

describe('AgentPanelPage gestão', () => {
  it('retoma a conversa somente em Ajustes, sem duplicar a chamada na página', async () => {
    const wrapper = mountPage({ tab: 'tune', resumeBuild: true });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'PanelSettings' }).props('resumeBuild')
    ).toBe(true);
    expect(context.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 42);
    expect(context.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      expect.anything()
    );
  });

  it('recarrega a projeção depois de salvar Ajustes ou associar um canal', async () => {
    const wrapper = mountPage({ tab: 'tune' });
    await flushPromises();
    wrapper
      .findComponent({ name: 'PanelSettings' })
      .vm.$emit('agentUpdated', { id: 42, name: 'Clara nova' });
    await flushPromises();
    await wrapper.setProps({ tab: 'channels' });
    wrapper.findComponent({ name: 'PanelWhereServes' }).vm.$emit('changed');
    await flushPromises();
    expect(context.dispatch).toHaveBeenCalledTimes(3);
  });

  it('leva Ensinar ao conhecimento do mesmo agente', async () => {
    const wrapper = mountPage({ tab: 'test' });
    await flushPromises();
    wrapper.findComponent({ name: 'PanelAgentTest' }).vm.$emit('teach');
    expect(context.push).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 42, tab: 'knowledge' },
    });
  });

  it('continua uma montagem manual em Ajustes novos', async () => {
    context.record.value = {
      ...context.record.value,
      mode: 'manual',
      state: { code: 'E2m' },
    };
    const wrapper = mountPage({ tab: 'tune' });
    await flushPromises();
    expect(wrapper.findComponent(shell).props('actionRoute')).toEqual({
      name: 'autonomia_agent_panel',
      params: { agentId: 42, tab: 'tune' },
    });
  });

  it('redireciona uma aba de gestão de quem só pode ver', async () => {
    context.canManage.value = false;
    const wrapper = mountPage({ tab: 'knowledge' });
    await flushPromises();
    expect(wrapper.findComponent({ name: 'PanelKnows' }).exists()).toBe(false);
    expect(wrapper.findComponent(shell).props('visibleTabs')).toEqual([
      'performance',
      'test',
    ]);
    expect(context.replace).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 42, tab: 'performance' },
    });
  });

  it('mantém cotação em ramos e oculta canais do interno', async () => {
    context.record.value = {
      ...context.record.value,
      agent_type: 'insurance_quote',
    };
    const quote = mountPage({ tab: 'knowledge' });
    await flushPromises();
    expect(quote.findComponent({ name: 'PanelQuoteKnowledge' }).exists()).toBe(
      true
    );
    context.record.value = {
      ...context.record.value,
      agent_type: 'custom',
      actuation: 'internal',
    };
    const internal = mountPage({ tab: 'tune' });
    await flushPromises();
    expect(internal.findComponent(shell).props('visibleTabs')).not.toContain(
      'channels'
    );
  });
});
