import { mount } from '@vue/test-utils';
import RecordReadOnly from '../RecordReadOnly.vue';
import LabelItem from 'dashboard/components-next/label/LabelItem.vue';

it('shows confirmed data without any form or mutation action', () => {
  const wrapper = mount(RecordReadOnly, {
    props: {
      rows: [
        { key: 'name', label: 'Name', value: 'Mariana' },
        { key: 'zero', label: 'Zero', value: 0 },
        { key: 'missing', label: 'Missing', value: '' },
      ],
    },
  });
  expect(wrapper.text()).toContain('Mariana');
  expect(wrapper.findAll('dd').map(item => item.text())).toEqual([
    'Mariana',
    '0',
    'CRM_KANBAN.RELATIONSHIP.NOT_INFORMED',
  ]);
  expect(wrapper.find('input,textarea,button,[contenteditable]').exists()).toBe(
    false
  );
  wrapper.unmount();
});
it('removes the label delete button from keyboard navigation for a read-only record', () => {
  const wrapper = mount(LabelItem, {
    props: {
      label: { id: 1, title: 'Client', color: 'blue' },
      readOnly: true,
      isHovered: true,
    },
  });
  expect(wrapper.text()).toBe('Client');
  expect(wrapper.find('button').exists()).toBe(false);
  wrapper.unmount();
});
