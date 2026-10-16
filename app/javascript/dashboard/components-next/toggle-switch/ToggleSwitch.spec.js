import { mount } from '@vue/test-utils';
import ToggleSwitch from './ToggleSwitch.vue';

// No documento, para o clique no trilho alternar como no navegador (o componente é um <label>).
const mountSwitch = modelValue =>
  mount(ToggleSwitch, {
    props: { label: 'Use WhatsApp API', modelValue },
    attachTo: document.body,
  });

describe('ToggleSwitch (#1487)', () => {
  it('is a checkbox with the switch role, 44 px target and a name', () => {
    const wrapper = mountSwitch(false);
    const input = wrapper.find('input');

    expect(wrapper.element.tagName).toBe('LABEL');
    expect(input.attributes('role')).toBe('switch');
    expect(input.attributes('aria-label')).toBe('Use WhatsApp API');
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['min-h-11', 'min-w-11'])
    );
    wrapper.unmount();
  });

  it('toggles when the track is clicked or tapped', async () => {
    const wrapper = mountSwitch(false);
    const input = wrapper.find('input');

    await wrapper.find('[data-toggle-track]').trigger('click');

    expect(input.element.checked).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
    wrapper.unmount();
  });
});
