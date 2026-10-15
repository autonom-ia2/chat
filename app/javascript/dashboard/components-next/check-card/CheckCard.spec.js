import { mount } from '@vue/test-utils';
import CheckCard from './CheckCard.vue';

describe('CheckCard (#1487)', () => {
  it('is a real checkbox named by its title, toggled by clicking the card', async () => {
    const wrapper = mount(CheckCard, {
      props: { title: 'Agents', description: 'When someone replies.' },
      slots: { selos: '<span data-badge>Recommended</span>' },
      // No documento, para o clique no rótulo marcar o campo como no navegador.
      attachTo: document.body,
    });
    const input = wrapper.find('input[type="checkbox"]');

    expect(wrapper.find('label').text()).toContain('Agents');
    expect(wrapper.find('[data-badge]').exists()).toBe(true);
    expect(wrapper.find('.font-semibold').classes()).toContain('leading-snug');
    expect(input.element.checked).toBe(false);
    await wrapper.find('label').trigger('click');

    expect(input.element.checked).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
    wrapper.unmount();
  });

  it('shows the check mark and the blue border when checked', () => {
    const wrapper = mount(CheckCard, {
      props: { title: 'Agents', modelValue: true },
    });

    expect(wrapper.find('label').classes()).toContain('border-n-blue-8');
    expect(wrapper.find('.i-lucide-check').exists()).toBe(true);
  });
});
