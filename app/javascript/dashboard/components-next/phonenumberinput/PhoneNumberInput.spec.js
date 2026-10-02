import { mount, flushPromises } from '@vue/test-utils';
import PhoneNumberInput from './PhoneNumberInput.vue';

const options = { global: { directives: { 'on-clickaway': {} } } };
it('accepts an optional blank phone through the public draft validator', async () => {
  const wrapper = mount(PhoneNumberInput, options);
  expect(await wrapper.vm.validate()).toBe(true);
  wrapper.unmount();
});
it('rejects invalid raw input even when its model retains the previously valid number', async () => {
  const wrapper = mount(PhoneNumberInput, {
    ...options,
    props: { modelValue: '+14155552671', ariaLabel: 'Optional phone' },
  });
  await flushPromises();
  const input = wrapper.find('input[type="tel"]');
  expect(input.attributes('aria-label')).toBe('Optional phone');
  await input.setValue('invalid');
  await flushPromises();
  expect(await wrapper.vm.validate()).toBe(false);
  expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).not.toBe('invalid');
  wrapper.unmount();
});
it('allows clearing a previously entered optional phone', async () => {
  const wrapper = mount(PhoneNumberInput, {
    ...options,
    props: { modelValue: '+14155552671' },
  });
  await flushPromises();
  await wrapper.find('input[type="tel"]').setValue('');
  await flushPromises();
  expect(await wrapper.vm.validate()).toBe(true);
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toBe('');
  wrapper.unmount();
});
