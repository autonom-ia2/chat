import { mount } from '@vue/test-utils';
import StepsBar from '../StepsBar.vue';

const campaignSteps = [
  { key: 'AUDIENCE', label: 'Audience' },
  { key: 'MESSAGE', label: 'Message' },
  { key: 'REVIEW', label: 'Review' },
];

const agentSteps = [
  { key: 'CHOICE', label: 'Escolha' },
  { key: 'TELL', label: 'Conte' },
  { key: 'TEST', label: 'Teste' },
  { key: 'LIVE', label: 'Ligue' },
];

const stepAria = (step, number) => `Step ${number}: ${step.label}`;

const mountStepsBar = props =>
  mount(StepsBar, {
    props,
    attachTo: document.body,
  });

describe('StepsBar (D9/F0)', () => {
  it('keeps the three-step Campaigns contract with generic labels and ARIA', async () => {
    const wrapper = mountStepsBar({
      steps: campaignSteps,
      current: 2,
      reachable: 2,
      ariaLabel: 'Campaign steps',
      stepAria,
    });
    const steps = wrapper.findAll('[data-step]');

    expect(steps).toHaveLength(3);
    expect(steps.map(step => step.attributes('aria-current'))).toEqual([
      undefined,
      'step',
      undefined,
    ]);
    expect(steps[1].attributes('aria-label')).toBe('Step 2: Message');
    expect(wrapper.find('nav').attributes('aria-label')).toBe('Campaign steps');
    expect(steps[2].attributes('disabled')).toBeDefined();

    await steps[0].trigger('click');
    expect(wrapper.emitted('go')).toEqual([[1]]);
    wrapper.unmount();
  });

  it('accepts exactly four Agent stages and keeps Pronto outside the step bar', () => {
    const wrapper = mountStepsBar({
      steps: agentSteps,
      current: 1,
      reachable: 1,
      ariaLabel: 'Agent steps',
      stepAria,
    });
    const steps = wrapper.findAll('[data-step]');

    expect(steps).toHaveLength(4);
    expect(wrapper.text()).toContain('Escolha');
    expect(wrapper.text()).toContain('Conte');
    expect(wrapper.text()).toContain('Teste');
    expect(wrapper.text()).toContain('Ligue');
    expect(wrapper.text()).not.toContain('Pronto');
    wrapper.unmount();
  });

  it('moves focus among reachable steps with Arrow, Home and End', async () => {
    const wrapper = mountStepsBar({
      steps: agentSteps,
      current: 3,
      reachable: 4,
      ariaLabel: 'Agent steps',
      stepAria,
    });
    const [first, second, , fourth] = wrapper.findAll('[data-step]');

    first.element.focus();
    await first.trigger('keydown', { key: 'ArrowRight' });
    expect(document.activeElement).toBe(second.element);
    await second.trigger('keydown', { key: 'End' });
    expect(document.activeElement).toBe(fourth.element);
    await fourth.trigger('keydown', { key: 'ArrowRight' });
    expect(document.activeElement).toBe(first.element);
    await first.trigger('keydown', { key: 'ArrowLeft' });
    expect(document.activeElement).toBe(fourth.element);
    await fourth.trigger('keydown', { key: 'Home' });
    expect(document.activeElement).toBe(first.element);
    wrapper.unmount();
  });
});
