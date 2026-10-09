import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

const currentAccount = ref({
  id: 7,
  autonomia_agents_redesign_enabled: true,
});

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount }),
}));
vi.mock('../../pages/AgentPanelPage.vue', () => ({
  __esModule: true,
  default: {
    name: 'LegacyAgentPanelPageMock',
    props: ['agentId', 'tab', 'resumeBuild'],
    template: '<div data-legacy-panel>{{ agentId }}:{{ tab }}</div>',
  },
}));
vi.mock('./AgentPanelPage.vue', () => ({
  __esModule: true,
  default: {
    name: 'RedesignAgentPanelPageMock',
    props: ['agentId', 'tab', 'resumeBuild'],
    template: '<div data-redesign-panel>{{ agentId }}:{{ tab }}</div>',
  },
}));

describe('AgentPanelEntry', () => {
  beforeEach(() => {
    currentAccount.value = {
      id: 7,
      autonomia_agents_redesign_enabled: true,
    };
  });

  it('escolhe a página nova com a flag da conta ligada', async () => {
    const { default: Entry } = await import('./AgentPanelEntry.vue');
    const wrapper = mount(Entry, {
      props: { agentId: 42, tab: 'performance' },
    });
    await flushPromises();

    expect(wrapper.find('[data-redesign-panel]').exists()).toBe(true);
    expect(wrapper.find('[data-legacy-panel]').exists()).toBe(false);
  });

  it('preserva o painel legado quando a flag está desligada', async () => {
    currentAccount.value.autonomia_agents_redesign_enabled = false;
    const { default: Entry } = await import('./AgentPanelEntry.vue');
    const wrapper = mount(Entry, { props: { agentId: 42, tab: 'test' } });
    await flushPromises();

    expect(wrapper.find('[data-legacy-panel]').exists()).toBe(true);
    expect(wrapper.find('[data-redesign-panel]').exists()).toBe(false);
  });
});
