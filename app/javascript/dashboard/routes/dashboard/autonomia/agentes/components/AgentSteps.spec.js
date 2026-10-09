import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enAgents from 'dashboard/i18n/locale/en/agents.json';
import ptAgents from 'dashboard/i18n/locale/pt_BR/agents.json';
import AgentSteps from './AgentSteps.vue';

const locales = [
  {
    locale: 'en',
    messages: enAgents,
    ariaLabel: 'Steps',
    steps: [
      'Step 1: Choose',
      'Step 2: Tell us',
      'Step 3: Test',
      'Step 4: Connect',
    ],
  },
  {
    locale: 'pt_BR',
    messages: ptAgents,
    ariaLabel: 'Etapas',
    steps: [
      'Etapa 1: Escolha',
      'Etapa 2: Conte',
      'Etapa 3: Teste',
      'Etapa 4: Ligue',
    ],
  },
];

describe('AgentSteps', () => {
  it.each(locales)(
    'usa o catálogo $locale nas quatro etapas e bloqueia o que ainda não está acessível',
    async ({ locale, messages, ariaLabel, steps: labels }) => {
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: { [locale]: messages },
      });
      const wrapper = mount(AgentSteps, {
        props: { current: 2, reachable: 3 },
        global: { plugins: [i18n] },
        attachTo: document.body,
      });
      const steps = wrapper.findAll('[data-step]');

      expect(steps).toHaveLength(4);
      expect(wrapper.find('nav').attributes('aria-label')).toBe(ariaLabel);
      expect(steps.map(step => step.attributes('aria-label'))).toEqual(labels);
      expect(steps[1].attributes('aria-current')).toBe('step');
      expect(steps[3].attributes('disabled')).toBeDefined();
      expect(wrapper.text()).toContain(labels[0].split(': ')[1]);
      expect(wrapper.text()).toContain(labels[1].split(': ')[1]);
      expect(wrapper.text()).toContain(labels[2].split(': ')[1]);
      expect(wrapper.text()).toContain(labels[3].split(': ')[1]);

      await steps[0].trigger('click');
      await steps[2].trigger('click');
      await steps[3].trigger('click');
      expect(wrapper.emitted('go')).toEqual([[1], [3]]);

      wrapper.unmount();
    }
  );
});
