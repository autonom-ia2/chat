import { mount } from '@vue/test-utils';
import AttributeDraftFields from '../AttributeDraftFields.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';

it.each([
  ['number', '0', 0],
  ['currency', '10.45', 10.45],
  ['percent', '5', 5],
  ['date', '2026-11-15', '2026-11-15'],
  ['text', 'Text', 'Text'],
  ['link', 'https://example.com', 'https://example.com'],
])('drafts %s without writing to a record', async (type, value, expected) => {
  const wrapper = mount(AttributeDraftFields, {
    props: {
      definitions: [
        {
          id: 1,
          attribute_key: 'value',
          attribute_display_name: 'Value',
          attribute_display_type: type,
        },
      ],
      modelValue: {},
    },
  });
  wrapper.findComponent(Input).vm.$emit('update:modelValue', value);
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
    value: expected,
  });
  wrapper.unmount();
});
it('offers blank, true and false separately for an optional checkbox', () => {
  const wrapper = mount(AttributeDraftFields, {
    props: {
      definitions: [
        {
          id: 1,
          attribute_key: 'enabled',
          attribute_display_name: 'Enabled',
          attribute_display_type: 'checkbox',
        },
      ],
      modelValue: { enabled: false },
    },
  });
  const select = wrapper.findComponent(ChoiceSelect);
  expect(select.props('modelValue')).toBe(false);
  expect(select.props('options').map(item => item.value)).toEqual([
    '',
    true,
    false,
  ]);
  select.vm.$emit('update:modelValue', true);
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
    enabled: true,
  });
  wrapper.unmount();
});
it('uses the real list catalog without a native select and shows a field-specific error', () => {
  const wrapper = mount(AttributeDraftFields, {
    props: {
      definitions: [
        {
          id: 1,
          attribute_key: 'channel',
          attribute_display_name: 'Channel',
          attribute_display_type: 'list',
          attribute_values: ['Email', 'Phone'],
        },
      ],
      modelValue: {},
      errors: { 'custom_attributes.channel': 'invalid' },
    },
  });
  expect(wrapper.findAll('select')).toHaveLength(0);
  expect(
    wrapper
      .findComponent(ChoiceSelect)
      .props('options')
      .map(item => item.value)
  ).toEqual(['', 'Email', 'Phone']);
  expect(wrapper.findComponent(ChoiceSelect).props('invalid')).toBe(true);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
