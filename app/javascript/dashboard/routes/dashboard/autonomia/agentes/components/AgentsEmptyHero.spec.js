import { mount } from '@vue/test-utils';

const loadComponent = () => import('./AgentsEmptyHero.vue');

describe('AgentsEmptyHero', () => {
  it('mostra três modelos de começo para quem pode editar', async () => {
    const { default: AgentsEmptyHero } = await loadComponent();
    const wrapper = mount(AgentsEmptyHero, {
      props: { canManage: true },
      global: { mocks: { $t: key => key } },
    });

    expect(wrapper.findAll('[data-model-card]')).toHaveLength(3);
    expect(wrapper.text()).toContain('AGENTS.V2.empty.title');
  });

  it('não mostra criação nem modelos para quem só pode ver', async () => {
    const { default: AgentsEmptyHero } = await loadComponent();
    const wrapper = mount(AgentsEmptyHero, {
      props: { canManage: false },
      global: { mocks: { $t: key => key } },
    });

    expect(wrapper.find('[data-create-agent]').exists()).toBe(false);
    expect(wrapper.findAll('[data-model-card]')).toHaveLength(0);
    expect(wrapper.text()).toContain('AGENTS.V2.empty.viewer');
  });
});
