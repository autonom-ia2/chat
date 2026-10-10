import { mount } from '@vue/test-utils';
import StepWhen from '../components/steps/StepWhen.vue';
import { pageToForm } from '../bookingPageForm';

// Passo "Quando" (#1195, J3-A13): "Fechar nos feriados nacionais" vem ligado e
// o admin pode desligar.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));

const page = {
  title: 'Vendas',
  duration_minutes: 30,
  working_hours: { start_hour: 9, end_hour: 17, weekdays: [1, 2, 3, 4, 5] },
};

const mountStep = form => mount(StepWhen, { props: { form } });

describe('StepWhen: feriados', () => {
  it('vem ligado numa página nova e diz que ninguém marca no feriado', () => {
    const wrapper = mountStep(pageToForm(page));
    const toggle = wrapper.find('[data-holidays]');

    expect(toggle.attributes('aria-pressed')).toBe('true');
    expect(toggle.text()).toContain('BOOKING.WHEN.HOLIDAYS_TOGGLE');
    expect(wrapper.text()).toContain('BOOKING.WHEN.HOLIDAYS_ON_HINT');
    expect(toggle.attributes('class')).toContain('min-h-11');
  });

  it('tocar desliga, e desligado tocar liga de novo', async () => {
    const wrapper = mountStep(pageToForm(page));
    await wrapper.find('[data-holidays]').trigger('click');
    expect(wrapper.emitted('change')).toEqual([[{ closeHolidays: false }]]);

    const off = mountStep(pageToForm({ ...page, close_holidays: false }));
    expect(off.find('[data-holidays]').attributes('aria-pressed')).toBe(
      'false'
    );
    expect(off.text()).toContain('BOOKING.WHEN.HOLIDAYS_OFF_HINT');
    await off.find('[data-holidays]').trigger('click');
    expect(off.emitted('change')).toEqual([[{ closeHolidays: true }]]);
  });
});
