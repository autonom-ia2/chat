import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PanelQuoteKnowledge from './PanelQuoteKnowledge.vue';

withFullI18n();
enableAutoUnmount(afterEach);

describe('PanelQuoteKnowledge', () => {
  it('mostra somente os ramos reais da Cotação, sem materiais ou ensino', () => {
    const wrapper = mount(PanelQuoteKnowledge, {
      props: {
        agent: {
          id: 42,
          agent_type: 'insurance_quote',
          quote_branches: [{ slug: 'auto', name: 'Automóvel' }],
        },
      },
      global: {
        mocks: { $t: key => key },
      },
    });

    expect(wrapper.text()).toContain('Automóvel');
    expect(wrapper.text()).not.toContain('AGENTS.KNOWLEDGE.ADD');
    expect(wrapper.text()).not.toContain('AGENTS.PANEL.REDESIGN_DRAWER.TEACH');
  });
});
