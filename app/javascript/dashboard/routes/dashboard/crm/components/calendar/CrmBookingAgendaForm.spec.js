import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../vitest.i18n';
import CrmBookingAgendaForm from './CrmBookingAgendaForm.vue';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';

// Dia em cartões (#1285): a janela "Agendar reunião" mostra só os dias em que
// a página atende, destaca o dia do horário mais cedo e troca de dia por
// clique ou teclado, carregando os horários do dia escolhido.
withFullI18n('pt_BR');

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { slots: vi.fn(), book: vi.fn() },
}));
vi.mock('dashboard/api/crmBookingInvites', () => ({
  default: { create: vi.fn(), deliver: vi.fn(), copied: vi.fn() },
}));

// Segunda, 19/10/2099, 23h30 em São Paulo: em UTC já é dia 20, e os cartões
// seguem o fuso da página.
const NOW = new Date('2099-10-19T23:30:00-03:00');
const PAGE = {
  id: 3,
  title: 'Conversa de 30 min',
  timezone: 'America/Sao_Paulo',
  duration_minutes: 30,
  durations: [30],
  notices: false,
  locations: [{ type: 'whatsapp_video', label: 'Vídeo no WhatsApp' }],
  booking_window_days: 14,
  weekdays: [1, 2, 3, 4, 5],
  closed_dates: ['2099-10-21'],
};
const slotAt = day => `${day}T10:00:00-03:00`;

// Cada dia responde com um horário às 10h, menos os de `empty`, que apontam
// o próximo livre em `next`.
const answerSlots = ({ empty = [], next = null } = {}) => {
  crmBookingPagesAPI.slots.mockImplementation((_id, { date }) =>
    Promise.resolve({
      data: {
        payload: empty.includes(date)
          ? { slots: [], next_slot: next }
          : { slots: [slotAt(date)], next_slot: null },
      },
    })
  );
};

const mountForm = async (props = {}) => {
  const wrapper = mount(CrmBookingAgendaForm, {
    props: { pages: [PAGE], cardId: 7, initialDay: '2099-10-19', ...props },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};

const cardDays = wrapper =>
  wrapper.findAll('[role="radio"]').map(card => card.attributes('data-day'));
const card = (wrapper, day) => wrapper.get(`[data-day="${day}"]`);
const checkedDay = wrapper =>
  wrapper.get('[role="radio"][aria-checked="true"]').attributes('data-day');

describe('CrmBookingAgendaForm', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    answerSlots();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('shows day cards for the days the page serves, never the native date field', async () => {
    const wrapper = await mountForm();

    expect(wrapper.find('input[type="date"]').exists()).toBe(false);
    // Sem fim de semana (24 e 25) e sem o feriado que a página fecha (21).
    expect(cardDays(wrapper)).toEqual([
      '2099-10-19',
      '2099-10-20',
      '2099-10-22',
      '2099-10-23',
      '2099-10-26',
      '2099-10-27',
      '2099-10-28',
    ]);
    const first = card(wrapper, '2099-10-19');
    expect(first.text()).toContain('seg.');
    expect(first.text()).toContain('19');
    expect(first.text()).toContain('out.');
  });

  it('names the group and each day for the screen reader', async () => {
    const wrapper = await mountForm();

    expect(wrapper.get('[role="radiogroup"]').attributes('aria-label')).toBe(
      'Dia'
    );
    expect(card(wrapper, '2099-10-20').attributes('aria-label')).toBe(
      'terça-feira, 20 de outubro'
    );
  });

  it('opens on the asked day and loads its free times', async () => {
    const wrapper = await mountForm({ initialDay: '2099-10-20' });

    expect(checkedDay(wrapper)).toBe('2099-10-20');
    expect(crmBookingPagesAPI.slots).toHaveBeenCalledWith(3, {
      date: '2099-10-20',
      duration: 30,
    });
    expect(wrapper.get('[data-booking-agenda-slots]').text()).toContain(
      '10:00'
    );
  });

  it('falls to the first offered day when the asked one is closed', async () => {
    const wrapper = await mountForm({ initialDay: '2099-10-21' });

    expect(checkedDay(wrapper)).toBe('2099-10-19');
  });

  it('loads the free times of the day that was clicked', async () => {
    const wrapper = await mountForm();
    crmBookingPagesAPI.slots.mockClear();

    await card(wrapper, '2099-10-22').trigger('click');
    await flushPromises();

    expect(checkedDay(wrapper)).toBe('2099-10-22');
    expect(crmBookingPagesAPI.slots).toHaveBeenCalledTimes(1);
    expect(crmBookingPagesAPI.slots).toHaveBeenCalledWith(3, {
      date: '2099-10-22',
      duration: 30,
    });
  });

  it('moves between days with the arrows, Home and End, with one Tab stop', async () => {
    const wrapper = await mountForm();
    const tabStops = () =>
      wrapper
        .findAll('[role="radio"]')
        .filter(item => item.attributes('tabindex') === '0')
        .map(item => item.attributes('data-day'));
    expect(tabStops()).toEqual(['2099-10-19']);

    await card(wrapper, '2099-10-19').trigger('keydown', { key: 'ArrowRight' });
    await flushPromises();
    expect(checkedDay(wrapper)).toBe('2099-10-20');
    expect(document.activeElement.getAttribute('data-day')).toBe('2099-10-20');
    expect(tabStops()).toEqual(['2099-10-20']);
    expect(crmBookingPagesAPI.slots).toHaveBeenLastCalledWith(3, {
      date: '2099-10-20',
      duration: 30,
    });

    await card(wrapper, '2099-10-20').trigger('keydown', { key: 'ArrowLeft' });
    expect(checkedDay(wrapper)).toBe('2099-10-19');

    await card(wrapper, '2099-10-19').trigger('keydown', { key: 'ArrowUp' });
    expect(checkedDay(wrapper)).toBe('2099-10-28');

    await card(wrapper, '2099-10-28').trigger('keydown', { key: 'ArrowDown' });
    expect(checkedDay(wrapper)).toBe('2099-10-19');

    // End vai ao último dia da janela, abrindo os cartões que faltavam.
    await card(wrapper, '2099-10-19').trigger('keydown', { key: 'End' });
    await flushPromises();
    expect(checkedDay(wrapper)).toBe('2099-11-02');
    expect(document.activeElement.getAttribute('data-day')).toBe('2099-11-02');
    expect(cardDays(wrapper)).toHaveLength(10);

    await card(wrapper, '2099-11-02').trigger('keydown', { key: 'Home' });
    expect(checkedDay(wrapper)).toBe('2099-10-19');
  });

  it('highlights the day of the earliest free time', async () => {
    answerSlots({ empty: ['2099-10-19'], next: slotAt('2099-10-22') });
    const wrapper = await mountForm({ initialDay: '2099-10-20' });

    const earliest = wrapper.findAll('[data-earliest]');
    expect(earliest.map(item => item.attributes('data-day'))).toEqual([
      '2099-10-22',
    ]);
    expect(earliest[0].text()).toContain('Mais cedo');
    expect(earliest[0].attributes('aria-label')).toBe(
      'quinta-feira, 22 de outubro, o dia livre mais cedo'
    );
  });

  it('without the answer about the earliest day, shows no highlight and the choice goes on', async () => {
    crmBookingPagesAPI.slots.mockImplementation((_id, { date }) =>
      date === '2099-10-19'
        ? Promise.reject(new Error('offline'))
        : Promise.resolve({
            data: { payload: { slots: [slotAt(date)], next_slot: null } },
          })
    );
    const wrapper = await mountForm({ initialDay: '2099-10-20' });

    expect(wrapper.find('[data-earliest]').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.get('[data-booking-agenda-slots]').text()).toContain(
      '10:00'
    );
  });

  it('reads the earliest day from the open day when it is the first one', async () => {
    const wrapper = await mountForm();

    expect(crmBookingPagesAPI.slots).toHaveBeenCalledTimes(1);
    expect(card(wrapper, '2099-10-19').text()).toContain('Mais cedo');
  });

  it('shows more days on demand and moves the focus to the first new one', async () => {
    const wrapper = await mountForm();
    expect(cardDays(wrapper)).toHaveLength(7);

    await wrapper.get('[data-booking-agenda-more-days]').trigger('click');
    await flushPromises();

    // A janela de 14 dias tem 10 dias de atendimento: não sobra o que mostrar.
    expect(cardDays(wrapper)).toEqual(
      expect.arrayContaining(['2099-10-29', '2099-10-30', '2099-11-02'])
    );
    expect(cardDays(wrapper)).toHaveLength(10);
    expect(document.activeElement.getAttribute('data-day')).toBe('2099-10-29');
    expect(wrapper.find('[data-booking-agenda-more-days]').exists()).toBe(
      false
    );
  });

  it('a day without free time still leads to the next free day, and shows its card', async () => {
    answerSlots({ empty: ['2099-10-19'], next: slotAt('2099-10-30') });
    const wrapper = await mountForm();

    expect(wrapper.text()).toContain('Nenhum horário livre neste dia.');
    await wrapper.get('[data-booking-agenda-next]').trigger('click');
    await flushPromises();

    expect(checkedDay(wrapper)).toBe('2099-10-30');
    expect(wrapper.get('[data-booking-agenda-slots]').text()).toContain(
      '10:00'
    );
  });

  it('changing to a page without open day drops the chosen time: nothing is booked', async () => {
    const closed = { ...PAGE, id: 4, title: 'Fechada', weekdays: [] };
    const wrapper = await mountForm({ pages: [PAGE, closed] });
    await wrapper.get('[data-booking-agenda-slots] button').trigger('click');

    await wrapper
      .getComponent('[data-booking-agenda-page]')
      .vm.$emit('update:modelValue', 4);
    await flushPromises();
    await wrapper.vm.submit();

    expect(wrapper.find('[data-booking-agenda-slots]').exists()).toBe(false);
    expect(crmBookingPagesAPI.book).not.toHaveBeenCalled();
  });

  it('says so when the page has no open day', async () => {
    const wrapper = await mountForm({
      pages: [{ ...PAGE, weekdays: [] }],
    });

    expect(wrapper.find('[role="radiogroup"]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'Esta página não tem dia aberto para marcar.'
    );
    expect(crmBookingPagesAPI.slots).not.toHaveBeenCalled();
  });
});
