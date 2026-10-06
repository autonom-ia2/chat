import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import JourneyStepper from '../JourneyStepper.vue';

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: enJourney },
});

const mountStepper = props =>
  mount(JourneyStepper, {
    props,
    attachTo: document.body,
    global: { plugins: [i18n] },
  });

describe('JourneyStepper (PRD §7, G4)', () => {
  it('marks only the current step with aria-current="step"', () => {
    const wrapper = mountStepper({ current: 2, reachable: 3 });
    const steps = wrapper.findAll('[data-step]');

    expect(steps.map(step => step.attributes('aria-current'))).toEqual([
      undefined,
      'step',
      undefined,
    ]);
    expect(steps[1].attributes('aria-label')).toBe('Step 2: Message');
    expect(wrapper.find('nav').attributes('aria-label')).toBe('Campaign steps');
    wrapper.unmount();
  });

  it('steps not reached yet are disabled; reached ones go back on click', async () => {
    const wrapper = mountStepper({ current: 2, reachable: 2 });

    expect(
      wrapper.find('[data-step="3"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.find('[data-step="3"]').trigger('click');
    await wrapper.find('[data-step="2"]').trigger('click');
    await wrapper.find('[data-step="1"]').trigger('click');

    expect(wrapper.emitted('go')).toEqual([[1]]);
    wrapper.unmount();
  });

  it('arrow keys, Home and End move focus between reachable steps', async () => {
    const wrapper = mountStepper({ current: 3, reachable: 3 });
    const [first, second, third] = wrapper.findAll('[data-step]');

    first.element.focus();
    await first.trigger('keydown', { key: 'ArrowRight' });
    expect(document.activeElement).toBe(second.element);
    await second.trigger('keydown', { key: 'End' });
    expect(document.activeElement).toBe(third.element);
    await third.trigger('keydown', { key: 'ArrowRight' });
    expect(document.activeElement).toBe(first.element);
    await first.trigger('keydown', { key: 'ArrowLeft' });
    expect(document.activeElement).toBe(third.element);
    await third.trigger('keydown', { key: 'Home' });
    expect(document.activeElement).toBe(first.element);
    wrapper.unmount();
  });
});
