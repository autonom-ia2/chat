import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

const currentAccount = ref({ id: 85, autonomia_agents_redesign_enabled: true });
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount }),
}));
vi.mock('./AgentCreationPage.vue', () => ({
  __esModule: true,
  default: {
    props: ['agentId', 'step'],
    template: '<div data-new-creation>{{ agentId }}:{{ step }}</div>',
  },
}));
vi.mock('../../pages/AgentBuilderPage.vue', () => ({
  __esModule: true,
  default: { template: '<div data-legacy-builder />' },
}));
vi.mock('../../pages/AgentPanelPage.vue', () => ({
  __esModule: true,
  default: {
    props: ['agentId', 'tab', 'resumeBuild'],
    template:
      '<div data-legacy-panel>{{ agentId }}:{{ tab }}:{{ resumeBuild }}</div>',
  },
}));

describe('Creation entry preserves the account flag and legacy routes', () => {
  beforeEach(() => {
    currentAccount.value = { id: 85, autonomia_agents_redesign_enabled: true };
  });

  it('passes the same agent and step to the new page when the flag is on', async () => {
    const { default: Entry } = await import('./AgentCreationEntry.vue');
    const wrapper = mount(Entry, { props: { agentId: '42', step: 'tell' } });
    await flushPromises();

    expect(wrapper.find('[data-new-creation]').text()).toBe('42:tell');
    expect(wrapper.find('[data-legacy-panel]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('uses the existing builder for a new agent when the flag is off', async () => {
    currentAccount.value.autonomia_agents_redesign_enabled = false;
    const { default: Entry } = await import('./AgentCreationEntry.vue');
    const wrapper = mount(Entry, { props: { step: 'choice' } });
    await flushPromises();

    expect(wrapper.find('[data-legacy-builder]').exists()).toBe(true);
    expect(wrapper.find('[data-new-creation]').exists()).toBe(false);
    wrapper.unmount();
  });

  it.each([
    ['tell', 'tune'],
    ['test', 'test'],
    ['live', 'publish'],
    ['ready', 'performance'],
  ])(
    'preserves the legacy agent and maps %s to %s without creating a thread',
    async (step, tab) => {
      currentAccount.value.autonomia_agents_redesign_enabled = false;
      const { default: Entry } = await import('./AgentCreationEntry.vue');
      const wrapper = mount(Entry, { props: { agentId: '42', step } });
      await flushPromises();

      expect(wrapper.find('[data-legacy-panel]').text()).toBe(`42:${tab}:true`);
      expect(wrapper.find('[data-new-creation]').exists()).toBe(false);
      wrapper.unmount();
    }
  );
});
