import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enCampaignJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import ptCampaignJourney from 'dashboard/i18n/locale/pt_BR/campaignJourney.json';
import JourneyStepBar from '../JourneyStepBar.vue';

const locales = [
  {
    locale: 'en',
    messages: enCampaignJourney,
    ariaLabel: 'Campaign steps',
    steps: [
      'Step 1: Audience',
      'Step 2: Message',
      'Step 3: Review and schedule',
    ],
  },
  {
    locale: 'pt_BR',
    messages: ptCampaignJourney,
    ariaLabel: 'Passos da campanha',
    steps: [
      'Passo 1: Público',
      'Passo 2: Mensagem',
      'Passo 3: Revisar e agendar',
    ],
  },
];

describe('JourneyStepBar', () => {
  it.each(locales)(
    'usa o catálogo $locale nas três etapas e bloqueia a etapa seguinte',
    async ({ locale, messages, ariaLabel, steps: labels }) => {
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: { [locale]: messages },
      });
      const wrapper = mount(JourneyStepBar, {
        props: { current: 2, reachable: 2 },
        global: { plugins: [i18n] },
        attachTo: document.body,
      });
      const steps = wrapper.findAll('[data-step]');

      expect(steps).toHaveLength(3);
      expect(wrapper.find('nav').attributes('aria-label')).toBe(ariaLabel);
      expect(steps.map(step => step.attributes('aria-label'))).toEqual(labels);
      expect(steps[1].attributes('aria-current')).toBe('step');
      expect(steps[2].attributes('disabled')).toBeDefined();
      expect(wrapper.text()).toContain(labels[0].split(': ')[1]);
      expect(wrapper.text()).toContain(labels[1].split(': ')[1]);
      expect(wrapper.text()).toContain(labels[2].split(': ')[1]);

      await steps[0].trigger('click');
      await steps[2].trigger('click');
      expect(wrapper.emitted('go')).toEqual([[1]]);

      wrapper.unmount();
    }
  );
});
