import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { withFullI18n } from 'test-i18n';

import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import AgentBookingForm from './AgentBookingForm.vue';

vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { get: vi.fn() },
}));

withFullI18n();

// ChoiceSelect is stubbed to expose its options and drive v-model, so the spec
// checks the choices without depending on the popover.
const stubs = {
  ChoiceSelect: {
    props: ['modelValue', 'options', 'ariaLabel'],
    emits: ['update:modelValue'],
    template: `<div class="choice">
      <button v-for="option in options" :key="String(option.value)"
        :data-value="String(option.value)" :data-selected="option.value === modelValue"
        @click="$emit('update:modelValue', option.value)">{{ option.label }}</button>
    </div>`,
  },
  NextButton: {
    props: ['label'],
    template: '<button class="save">{{ label }}</button>',
  },
};

const PAGES = [
  { id: 7, title: 'Conversa de 30 min', enabled: true },
  { id: 9, title: 'Visita', enabled: false },
];

const mountForm = async agent => {
  const wrapper = mount(AgentBookingForm, {
    props: { agent },
    global: { stubs },
  });
  await flushPromises();
  return wrapper;
};

describe('AgentBookingForm', () => {
  beforeEach(() => {
    CrmBookingPagesAPI.get.mockReset();
  });

  it('offers "do not book" and each page, preselecting the saved one', async () => {
    CrmBookingPagesAPI.get.mockResolvedValue({ data: { payload: PAGES } });
    const wrapper = await mountForm({ config: { booking_page_id: 7 } });

    const options = wrapper.findAll('.choice button');
    expect(options.map(option => option.text())).toEqual([
      "Don't book",
      'Conversa de 30 min',
      'Visita (paused)',
    ]);
    expect(wrapper.find('[data-value="7"]').attributes('data-selected')).toBe(
      'true'
    );
  });

  it('emits the chosen page id, and null when the agent stops booking', async () => {
    CrmBookingPagesAPI.get.mockResolvedValue({ data: { payload: PAGES } });
    const wrapper = await mountForm({ config: {} });

    await wrapper.find('[data-value="7"]').trigger('click');
    await wrapper.find('button.save').trigger('click');
    await wrapper.find('[data-value=""]').trigger('click');
    await wrapper.find('button.save').trigger('click');

    expect(wrapper.emitted('submit')).toEqual([[7], [null]]);
  });

  it('warns when the chosen page is paused', async () => {
    CrmBookingPagesAPI.get.mockResolvedValue({ data: { payload: PAGES } });
    const wrapper = await mountForm({ config: { booking_page_id: 9 } });

    expect(wrapper.find('[data-test="agent-booking-paused"]').exists()).toBe(
      true
    );
  });

  it('shows how to create a page when the account has none', async () => {
    CrmBookingPagesAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountForm({ config: {} });

    expect(wrapper.find('[data-test="agent-booking-empty"]').exists()).toBe(
      true
    );
    expect(wrapper.find('button.save').exists()).toBe(false);
  });

  it('stays hidden when the account has no booking pages API (flag off)', async () => {
    CrmBookingPagesAPI.get.mockRejectedValue(new Error('404'));
    const wrapper = await mountForm({ config: {} });

    expect(wrapper.find('section').exists()).toBe(false);
  });
});
