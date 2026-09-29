import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import MediaContactSelect from '../MediaContactSelect.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

it('focuses search, preserves the selected real name across searches and restores focus on closing', async () => {
  const wrapper = mount(MediaContactSelect, {
    props: {
      options: [{ value: '4', label: 'Contato autorizado' }],
      modelValue: '4',
    },
    global: { stubs: { teleport: true } },
    attachTo: document.body,
  });
  const trigger = wrapper.find('button[aria-label="RELATIONSHIPS.CONTACTS"]');
  await trigger.trigger('click');
  await flushPromises();
  const input = wrapper.find('input');
  expect(document.activeElement).toBe(input.element);
  await input.setValue('outro');
  expect(wrapper.emitted('search').at(-1)).toEqual(['outro']);
  await wrapper.setProps({ options: [{ value: '5', label: 'Outro contato' }] });
  expect(trigger.text()).toBe('Contato autorizado');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Outro contato')
    .trigger('click');
  await flushPromises();
  expect(wrapper.emitted('update:modelValue')).toEqual([['5']]);
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(document.activeElement).toBe(trigger.element);
  await wrapper.setProps({ modelValue: '5' });
  expect(trigger.text()).toBe('Outro contato');
  await trigger.trigger('click');
  await flushPromises();
  expect(wrapper.find('input').element.value).toBe('');
  wrapper.unmount();
});
