import { mount } from '@vue/test-utils';

const loadComponent = () => import('./AgentsSummaryChips.vue');

describe('AgentsSummaryChips', () => {
  it('resume atendendo, pausados e pendências a partir de state.code', async () => {
    const { default: AgentsSummaryChips } = await loadComponent();
    const wrapper = mount(AgentsSummaryChips, {
      props: {
        agents: [
          { id: 'a', state: { code: 'E5' } },
          { id: 'b', state: { code: 'E6' } },
          { id: 'c', state: { code: 'E1' } },
          { id: 'd', state: { code: 'E3' } },
        ],
      },
      global: { mocks: { $t: key => key } },
    });

    expect(wrapper.text()).toContain('AGENTS.V2.summary.active');
    expect(wrapper.text()).toContain('AGENTS.V2.summary.paused');
    expect(wrapper.text()).toContain('AGENTS.V2.summary.toFinish');
    expect(wrapper.text()).toContain('2');
  });

  it('não cria chip de pendências quando não há E1 a E4', async () => {
    const { default: AgentsSummaryChips } = await loadComponent();
    const wrapper = mount(AgentsSummaryChips, {
      props: { agents: [{ state: { code: 'E5' } }] },
      global: { mocks: { $t: key => key } },
    });

    expect(wrapper.text()).not.toContain('AGENTS.V2.summary.toFinish');
  });
});
