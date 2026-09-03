import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import { withFullI18n } from 'test-i18n';

import AgentScheduleForm from './AgentScheduleForm.vue';

withFullI18n();

// RadioCard is stubbed to a plain button that forwards `select`, so the spec
// drives the same event the real card emits.
const stubs = {
  RadioCard: {
    props: ['id', 'label', 'isActive'],
    template:
      '<button :data-id="id" :data-active="isActive" @click="$emit(\'select\', id)">{{ label }}</button>',
  },
  NextButton: {
    props: ['label'],
    template: '<button class="save">{{ label }}</button>',
  },
};

const mountForm = agent =>
  mount(AgentScheduleForm, { props: { agent }, global: { stubs } });

describe('AgentScheduleForm', () => {
  it('offers the three windows and preselects the saved one', () => {
    const wrapper = mountForm({
      config: { response_window: 'business_hours' },
    });
    const cards = wrapper.findAll('button[data-id]');

    expect(cards.map(card => card.attributes('data-id'))).toEqual([
      'always',
      'business_hours',
      'outside_business_hours',
    ]);
    expect(cards[1].attributes('data-active')).toBe('true');
    expect(cards[1].text()).toBe('During business hours');
  });

  it('defaults to anytime and emits the chosen window on save', async () => {
    const wrapper = mountForm({ config: {} });
    expect(
      wrapper.find('button[data-id="always"]').attributes('data-active')
    ).toBe('true');

    await wrapper
      .find('button[data-id="outside_business_hours"]')
      .trigger('click');
    await wrapper.find('button.save').trigger('click');

    expect(wrapper.emitted('submit')).toEqual([['outside_business_hours']]);
  });
});
