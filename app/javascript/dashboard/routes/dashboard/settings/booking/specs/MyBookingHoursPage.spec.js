import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import MyBookingHoursAPI from 'dashboard/api/crmMyBookingHours';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import MyBookingHoursPage from '../MyBookingHoursPage.vue';

// Meus horários (#1195, J8-A11): a pessoa ajusta os próprios dias e horas só
// dentro do limite das páginas e pausa a própria agenda.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMyBookingHours', () => ({
  default: {
    show: vi.fn(),
    save: vi.fn(),
    usePageHours: vi.fn(),
    setPaused: vi.fn(),
  },
}));

const payload = (extra = {}) => ({
  paused: false,
  custom_hours: false,
  weekdays: [1, 2, 3, 4, 5],
  start_hour: 9,
  end_hour: 17,
  limits: { weekdays: [1, 2, 3, 4, 5], start_hour: 9, end_hour: 17 },
  pages: [{ id: 3, title: 'Vendas' }],
  ...extra,
});

const mountPage = async data => {
  MyBookingHoursAPI.show.mockResolvedValue({ data: { payload: data } });
  const wrapper = mount(MyBookingHoursPage);
  await flushPromises();
  return wrapper;
};

describe('MyBookingHoursPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('só oferece dias e horas dentro do limite das páginas', async () => {
    const wrapper = await mountPage(
      payload({
        limits: { weekdays: [1, 3], start_hour: 10, end_hour: 14 },
        weekdays: [1, 3],
        start_hour: 10,
        end_hour: 14,
      })
    );

    const days = wrapper
      .findAll('[data-day]')
      .map(item => item.attributes('data-day'));
    expect(days).toEqual(['1', '3']);
    const [start, end] = wrapper.findAllComponents(ChoiceSelect);
    expect(start.props('options').map(item => item.value)).toEqual([
      10, 11, 12, 13,
    ]);
    expect(end.props('options').map(item => item.value)).toEqual([
      11, 12, 13, 14,
    ]);
    expect(wrapper.find('[data-limit]').text()).toContain(
      'BOOKING.MY_HOURS.LIMIT'
    );
  });

  it('salva os dias e horas escolhidos', async () => {
    MyBookingHoursAPI.save.mockResolvedValue({
      data: {
        payload: payload({
          custom_hours: true,
          weekdays: [1, 2],
          start_hour: 10,
          end_hour: 16,
        }),
      },
    });
    const wrapper = await mountPage(payload());

    await wrapper.find('[data-day="3"]').trigger('click');
    await wrapper.find('[data-day="4"]').trigger('click');
    await wrapper.find('[data-day="5"]').trigger('click');
    const [start, end] = wrapper.findAllComponents(ChoiceSelect);
    start.vm.$emit('update:modelValue', 10);
    end.vm.$emit('update:modelValue', 16);
    await flushPromises();
    await wrapper.find('[data-save]').trigger('click');
    await flushPromises();

    expect(MyBookingHoursAPI.save).toHaveBeenCalledWith({
      weekdays: [1, 2],
      startHour: 10,
      endHour: 16,
    });
    expect(useAlert).toHaveBeenCalledWith('BOOKING.MY_HOURS.SAVED');
    expect(wrapper.find('[data-use-page]').exists()).toBe(true);
  });

  it('sem dia escolhido não manda nada e explica como pausar', async () => {
    const wrapper = await mountPage(payload({ weekdays: [1] }));
    await wrapper.find('[data-day="1"]').trigger('click');
    await wrapper.find('[data-save]').trigger('click');
    await flushPromises();

    expect(MyBookingHoursAPI.save).not.toHaveBeenCalled();
    expect(wrapper.find('[data-problem]').text()).toBe(
      'BOOKING.MY_HOURS.ERRORS.DAYS'
    );
  });

  it('fim antes do início não manda nada', async () => {
    const wrapper = await mountPage(payload());
    const [start, end] = wrapper.findAllComponents(ChoiceSelect);
    start.vm.$emit('update:modelValue', 15);
    end.vm.$emit('update:modelValue', 12);
    await flushPromises();
    await wrapper.find('[data-save]').trigger('click');

    expect(MyBookingHoursAPI.save).not.toHaveBeenCalled();
    expect(wrapper.find('[data-problem]').text()).toBe(
      'BOOKING.MY_HOURS.ERRORS.HOURS'
    );
  });

  it('recusa do servidor por passar do limite vira aviso próprio', async () => {
    MyBookingHoursAPI.save.mockRejectedValue({
      response: { data: { error: 'crm.booking_v2.my_hours_outside_page' } },
    });
    const wrapper = await mountPage(payload());
    await wrapper.find('[data-save]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-problem]').text()).toBe(
      'BOOKING.MY_HOURS.ERRORS.OUTSIDE'
    );
  });

  it('pausa e volta a agenda', async () => {
    MyBookingHoursAPI.setPaused.mockResolvedValueOnce({
      data: { payload: payload({ paused: true }) },
    });
    const wrapper = await mountPage(payload());
    const pause = wrapper.find('[data-pause]');
    expect(pause.attributes('aria-pressed')).toBe('false');

    await pause.trigger('click');
    await flushPromises();

    expect(MyBookingHoursAPI.setPaused).toHaveBeenCalledWith(true);
    expect(wrapper.find('[data-pause]').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(wrapper.find('[data-pause-card]').text()).toContain(
      'BOOKING.MY_HOURS.PAUSED_HINT'
    );
    expect(useAlert).toHaveBeenCalledWith('BOOKING.MY_HOURS.PAUSED_OK');

    MyBookingHoursAPI.setPaused.mockResolvedValueOnce({
      data: { payload: payload({ paused: false }) },
    });
    await wrapper.find('[data-pause]').trigger('click');
    await flushPromises();
    expect(MyBookingHoursAPI.setPaused).toHaveBeenLastCalledWith(false);
  });

  it('volta a seguir a página', async () => {
    MyBookingHoursAPI.usePageHours.mockResolvedValue({
      data: { payload: payload() },
    });
    const wrapper = await mountPage(
      payload({ custom_hours: true, start_hour: 10 })
    );

    await wrapper.find('[data-use-page]').trigger('click');
    await flushPromises();

    expect(MyBookingHoursAPI.usePageHours).toHaveBeenCalled();
    expect(wrapper.find('[data-use-page]').exists()).toBe(false);
  });

  it('sem página: só a pausa, com explicação', async () => {
    const wrapper = await mountPage(
      payload({ limits: null, pages: [], weekdays: null, start_hour: null })
    );

    expect(wrapper.find('[data-no-pages]').exists()).toBe(true);
    expect(wrapper.find('[data-hours]').exists()).toBe(false);
    expect(wrapper.find('[data-pause]').exists()).toBe(true);
  });

  it('quem não atende reuniões (401) vê uma frase, sem formulário', async () => {
    MyBookingHoursAPI.show.mockRejectedValue({ response: { status: 401 } });
    const wrapper = mount(MyBookingHoursPage);
    await flushPromises();

    expect(wrapper.find('[data-denied]').text()).toBe(
      'BOOKING.MY_HOURS.DENIED'
    );
    expect(wrapper.find('[data-pause]').exists()).toBe(false);
  });
});
