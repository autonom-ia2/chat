import { config, flushPromises, mount } from '@vue/test-utils';
import BookingStatsAPI from 'dashboard/api/crmBookingStats';
import BookingResultsPage from '../BookingResultsPage.vue';

// Painel de resultados (#1194, J7-A1/A3, J8-A12): cinco números com frase,
// origem, período em botões, "só os meus" x equipe, vazio e erro.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'settings_booking_results', params: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// "Voltar para o calendário" (#1212) só aparece para quem abre o Calendário.
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { ref } = await import('vue');
    return { useCrmPermissions: () => ({ canViewCrm: ref(true) }) };
  }
);
vi.mock('dashboard/api/crmBookingStats', () => ({
  default: { show: vi.fn(), openedNotBooked: vi.fn(), resend: vi.fn() },
}));

config.global.stubs = {
  RouterLink: { props: ['to'], template: '<a :data-to="to.name"><slot /></a>' },
};

const totals = {
  sent: 48,
  opened: 31,
  booked: 19,
  confirmed: 12,
  attended: 15,
  no_show: 4,
};
const stats = (overrides = {}) => ({
  data: {
    period: { days: 30 },
    scope: 'team',
    can_see_team: true,
    totals,
    origins: [
      { key: 'conversation', count: 12 },
      { key: 'public_link', count: 5 },
      { key: 'contact_request', count: 2 },
    ],
    ...overrides,
  },
});

const mountPage = props => mount(BookingResultsPage, { props });

describe('BookingResultsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    BookingStatsAPI.show.mockResolvedValue(stats());
    BookingStatsAPI.openedNotBooked.mockResolvedValue({
      data: { payload: [], meta: { page: 1, total: 0 } },
    });
  });

  it('mostra os cinco números, cada um com a frase que explica, e quantos confirmaram', async () => {
    const wrapper = mountPage();
    await flushPromises();

    const cards = wrapper.findAll('[data-number]');
    expect(cards.map(card => card.attributes('data-number'))).toEqual([
      'sent',
      'opened',
      'booked',
      'attended',
      'no_show',
    ]);
    expect(cards.map(card => card.get('[data-value]').text())).toEqual([
      '48',
      '31',
      '19',
      '15',
      '4',
    ]);
    expect(cards[0].text()).toContain('BOOKING.RESULTS.NUMBERS.SENT.HINT');
    expect(wrapper.get('[data-confirmed]').text()).toBe(
      'BOOKING.RESULTS.CONFIRMED {"count":12}'
    );
  });

  it('separa os horários marcados por origem, com o número escrito ao lado da barra', async () => {
    const wrapper = mountPage();
    await flushPromises();

    const origins = wrapper.findAll('[data-origin]');
    expect(origins.map(origin => origin.attributes('data-origin'))).toEqual([
      'conversation',
      'public_link',
      'contact_request',
    ]);
    expect(origins[0].text()).toContain('12');
    expect(origins[0].find('.w-full').exists()).toBe(true);
  });

  it('tem o Voltar para o calendário na aba do Agendamento, não em Meus números', async () => {
    const tab = mountPage({ entry: 'settings' });
    await flushPromises();
    const back = tab.find('[data-back-to-calendar]');
    expect(back.attributes('data-to')).toBe('crm_calendar_index');
    expect(back.text()).toBe('BOOKING.PAGE.BACK_TO_CALENDAR');

    const mine = mountPage({ entry: 'crm' });
    await flushPromises();
    expect(mine.find('[data-back-to-calendar]').exists()).toBe(false);
  });

  it('pede a equipe na porta do Agendamento e "só os meus" na porta do CRM', async () => {
    mountPage({ entry: 'settings' });
    await flushPromises();
    expect(BookingStatsAPI.show).toHaveBeenLastCalledWith({
      period: 30,
      scope: undefined,
    });

    BookingStatsAPI.show.mockResolvedValue(
      stats({ scope: 'mine', can_see_team: false })
    );
    const crm = mountPage({ entry: 'crm' });
    await flushPromises();
    expect(BookingStatsAPI.show).toHaveBeenLastCalledWith({
      period: 30,
      scope: 'mine',
    });
    expect(crm.find('[data-tab]').exists()).toBe(false);
    expect(crm.text()).toContain('BOOKING.RESULTS.TITLE_MINE');
  });

  it('troca o período por botões e só mostra "de quem" para quem pode ver a equipe', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('select').exists()).toBe(false);
    const sevenDays = wrapper.get('[data-toggle="7"]');
    expect(wrapper.get('[data-toggle="30"]').attributes('aria-pressed')).toBe(
      'true'
    );

    await sevenDays.trigger('click');
    await flushPromises();
    expect(BookingStatsAPI.show).toHaveBeenLastCalledWith({
      period: 7,
      scope: 'team',
    });
    expect(wrapper.get('[data-toggle="7"]').attributes('aria-pressed')).toBe(
      'true'
    );

    await wrapper.get('[data-toggle="mine"]').trigger('click');
    await flushPromises();
    expect(BookingStatsAPI.show).toHaveBeenLastCalledWith({
      period: 7,
      scope: 'mine',
    });

    BookingStatsAPI.show.mockResolvedValue(
      stats({ scope: 'mine', can_see_team: false })
    );
    const agent = mountPage({ entry: 'crm' });
    await flushPromises();
    expect(agent.find('[data-toggle="team"]').exists()).toBe(false);
  });

  it('período sem nada: uma frase e um botão que abre os 30 dias', async () => {
    const zero = { sent: 0, opened: 0, booked: 0, attended: 0, no_show: 0 };
    BookingStatsAPI.show.mockResolvedValue(stats({ totals: zero }));
    const wrapper = mountPage();
    await flushPromises();
    await wrapper.get('[data-toggle="7"]').trigger('click');
    await flushPromises();

    const empty = wrapper.get('[data-empty]');
    expect(empty.findAll('p')).toHaveLength(1);
    expect(empty.findAll('button')).toHaveLength(1);
    expect(wrapper.find('[data-number]').exists()).toBe(false);

    await wrapper.get('[data-empty-action]').trigger('click');
    await flushPromises();
    expect(BookingStatsAPI.show).toHaveBeenLastCalledWith({
      period: 30,
      scope: 'team',
    });
  });

  it('falha ao carregar: avisa e deixa tentar de novo', async () => {
    BookingStatsAPI.show.mockRejectedValueOnce(new Error('rede'));
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.get('[data-error]').attributes('role')).toBe('alert');
    await wrapper.get('[data-error] button').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-number]')).toHaveLength(5);
  });
});
