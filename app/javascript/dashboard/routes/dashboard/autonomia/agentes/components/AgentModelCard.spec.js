import { mount } from '@vue/test-utils';

const loadComponent = () => import('./AgentModelCard.vue');

describe('AgentModelCard', () => {
  it('emite o tipo de modelo sem fazer POST na lista', async () => {
    const { default: AgentModelCard } = await loadComponent();
    const wrapper = mount(AgentModelCard, {
      props: {
        model: {
          id: 'support',
          title: 'Tirar dúvidas',
          description: 'Responde perguntas comuns.',
        },
      },
      global: { mocks: { $t: key => key } },
    });

    await wrapper.find('[data-model-card]').trigger('click');
    expect(wrapper.emitted('select')).toEqual([['support']]);
  });
});
