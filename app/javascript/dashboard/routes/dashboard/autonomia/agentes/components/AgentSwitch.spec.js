import { mount } from '@vue/test-utils';
import AgentSwitch from './AgentSwitch.vue';

const mountSwitch = props =>
  mount(AgentSwitch, {
    props: {
      checked: false,
      disabled: false,
      label: 'Pausado',
      ariaLabel: 'Pausado: Clara',
      ...props,
    },
    attachTo: document.body,
  });

describe('AgentSwitch', () => {
  it('emite false ao desligar um agente atendendo', async () => {
    const wrapper = mountSwitch({
      checked: true,
      label: 'Atendendo',
      ariaLabel: 'Atendendo: Clara',
    });
    const control = wrapper.find('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('true');
    expect(control.attributes('aria-label')).toBe('Atendendo: Clara');
    expect(control.text()).toContain('Atendendo');

    await control.trigger('click');

    expect(wrapper.emitted('toggle')).toEqual([[false]]);
    wrapper.unmount();
  });

  it('emite true ao religar um agente pausado', async () => {
    const wrapper = mountSwitch({
      checked: false,
      label: 'Pausado',
      ariaLabel: 'Pausado: Clara',
    });
    const control = wrapper.find('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('false');
    expect(control.attributes('aria-label')).toBe('Pausado: Clara');
    expect(control.text()).toContain('Pausado');

    await control.trigger('click');

    expect(wrapper.emitted('toggle')).toEqual([[true]]);
    wrapper.unmount();
  });

  it('marca o controle como disabled quando a ação não está disponível', () => {
    const wrapper = mountSwitch({
      checked: true,
      disabled: true,
      label: 'Atendendo',
      ariaLabel: 'Atendendo: Clara',
    });
    const control = wrapper.find('[role="switch"]');

    expect(control.attributes('disabled')).toBeDefined();
    expect(control.attributes('aria-checked')).toBe('true');

    wrapper.unmount();
  });
});
