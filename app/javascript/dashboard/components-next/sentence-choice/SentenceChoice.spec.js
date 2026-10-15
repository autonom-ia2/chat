import { mount } from '@vue/test-utils';
import SentenceChoice from './SentenceChoice.vue';

const OPTIONS = [
  { value: 10, label: '10' },
  { value: 20, label: '20' },
  { value: 'other', label: 'Other' },
];

const mountChoice = modelValue =>
  mount(SentenceChoice, {
    props: {
      options: OPTIONS,
      label: 'Messages per minute',
      modelValue,
    },
    attachTo: document.body,
  });

describe('SentenceChoice (#1487)', () => {
  it('is a radio group with the checked option as the only tab stop', () => {
    const wrapper = mountChoice(20);
    const radios = wrapper.findAll('[role="radio"]');

    expect(wrapper.find('[role="radiogroup"]').attributes('aria-label')).toBe(
      'Messages per minute'
    );
    expect(radios.map(radio => radio.attributes('aria-checked'))).toEqual([
      'false',
      'true',
      'false',
    ]);
    expect(radios.map(radio => radio.attributes('tabindex'))).toEqual([
      '-1',
      '0',
      '-1',
    ]);
    wrapper.unmount();
  });

  it('lets the first option take the tab when nothing is checked', () => {
    const wrapper = mountChoice(99);

    expect(wrapper.findAll('[role="radio"]')[0].attributes('tabindex')).toBe(
      '0'
    );
    wrapper.unmount();
  });

  it('moves and checks with the arrows, wrapping around', async () => {
    const wrapper = mountChoice(20);
    const radios = wrapper.findAll('[role="radio"]');

    await radios[1].trigger('keydown', { key: 'ArrowRight' });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['other']);

    await radios[0].trigger('keydown', { key: 'ArrowLeft' });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['other']);

    await radios[2].trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([10]);
    wrapper.unmount();
  });

  it('checks on click', async () => {
    const wrapper = mountChoice(20);

    await wrapper.findAll('[role="radio"]')[0].trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([10]);
    wrapper.unmount();
  });
});
