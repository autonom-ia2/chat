import { mount } from '@vue/test-utils';
import ToggleSwitch from './ToggleSwitch.vue';

describe('ToggleSwitch (#1487)', () => {
  it('is a checkbox with the switch role, 44 px target and a name', async () => {
    const wrapper = mount(ToggleSwitch, {
      props: { label: 'Use WhatsApp API', modelValue: false },
    });
    const input = wrapper.find('input');

    expect(input.attributes('role')).toBe('switch');
    expect(input.attributes('aria-label')).toBe('Use WhatsApp API');
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['min-h-11', 'min-w-11'])
    );
    await input.setValue(true);

    expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
  });
});
