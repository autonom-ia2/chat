import { mount } from '@vue/test-utils';
import LabeledSwitch from '../LabeledSwitch.vue';

describe('LabeledSwitch (D9/F0)', () => {
  it('preserves the labeled switch contract and emits toggle', async () => {
    const wrapper = mount(LabeledSwitch, {
      props: {
        checked: true,
        label: 'Canal ativo',
        ariaLabel: 'Ativar canal',
      },
    });
    const control = wrapper.get('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('true');
    expect(control.attributes('aria-label')).toBe('Ativar canal');
    expect(control.classes()).toContain('min-h-11');
    expect(control.text()).toContain('Canal ativo');

    await control.trigger('click');
    expect(wrapper.emitted('toggle')).toEqual([[]]);
    wrapper.unmount();
  });

  it('preserves checked=false and disabled semantics', () => {
    const wrapper = mount(LabeledSwitch, {
      props: {
        checked: false,
        disabled: true,
        label: 'Canal inativo',
      },
    });
    const control = wrapper.get('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('false');
    expect(control.attributes('disabled')).toBeDefined();
    expect(control.text()).toContain('Canal inativo');
    wrapper.unmount();
  });
});
