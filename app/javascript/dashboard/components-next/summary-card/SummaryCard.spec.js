import { mount } from '@vue/test-utils';
import SummaryCard from './SummaryCard.vue';

const ButtonStub = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

const mountCard = props =>
  mount(SummaryCard, {
    props: { name: 'pace', icon: 'i-lucide-gauge', title: 'Pace', ...props },
    slots: { default: 'Up to 20 per minute.' },
    global: { stubs: { Button: ButtonStub } },
  });

describe('SummaryCard (#1487)', () => {
  it('shows the sentence and emits edit from "Change"', async () => {
    const wrapper = mountCard({ editLabel: 'Change' });

    expect(wrapper.text()).toContain('Up to 20 per minute.');
    await wrapper.find('button').trigger('click');

    expect(wrapper.emitted('edit')).toHaveLength(1);
  });

  it('dims and hides "Change" when the part does not apply now', () => {
    const wrapper = mountCard({ editLabel: 'Change', dimmed: true });

    expect(wrapper.find('article').attributes('aria-disabled')).toBe('true');
    expect(wrapper.find('button').exists()).toBe(false);
  });
});
