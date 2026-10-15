import { mount } from '@vue/test-utils';
import CheckCard from './CheckCard.vue';

describe('CheckCard (#1487)', () => {
  it('is a real checkbox named by its title, toggled by clicking the card', async () => {
    const wrapper = mount(CheckCard, {
      props: { title: 'Agents', description: 'When someone replies.' },
      slots: { selos: '<span data-badge>Recommended</span>' },
    });
    const input = wrapper.find('input[type="checkbox"]');

    expect(wrapper.find('label').text()).toContain('Agents');
    expect(wrapper.find('[data-badge]').exists()).toBe(true);
    await input.setValue(true);

    expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
  });

  it('shows the check mark and the blue border when checked', () => {
    const wrapper = mount(CheckCard, {
      props: { title: 'Agents', modelValue: true },
    });

    expect(wrapper.find('label').classes()).toContain('border-n-blue-8');
    expect(wrapper.find('.i-lucide-check').exists()).toBe(true);
  });
});
