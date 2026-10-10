import { flushPromises, mount } from '@vue/test-utils';
import BookingStatsAPI from 'dashboard/api/crmBookingStats';
import { useAlert } from 'dashboard/composables';
import OpenedNotBookedList from '../OpenedNotBookedList.vue';

// "Abriram e não marcaram" (#1194, J7-A4, J8-A12): uma linha por cliente,
// "Enviar de novo" só no toque, estado enviado, recusa da janela, vazio e
// "Ver mais".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmBookingStats', () => ({
  default: { show: vi.fn(), openedNotBooked: vi.fn(), resend: vi.fn() },
}));

const row = (overrides = {}) => ({
  id: 7,
  contact: { name: 'Paula Reis' },
  opened_at: '2026-10-07T15:00:00Z',
  page: { title: 'Conversa de 30 min' },
  sent_by: { name: 'Camila' },
  can_resend: true,
  resent_at: null,
  ...overrides,
});
const listOf = (payload, meta = { page: 1, total: payload.length }) => ({
  data: { payload, meta },
});

const mountList = (props = {}, options = {}) =>
  mount(OpenedNotBookedList, {
    props: { period: 30, scope: 'mine', ...props },
    ...options,
  });

describe('OpenedNotBookedList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    BookingStatsAPI.openedNotBooked.mockResolvedValue(listOf([row()]));
  });

  it('pede a lista do período e do escopo e mostra quem abriu, quando e por qual link', async () => {
    const wrapper = mountList();
    await flushPromises();

    expect(BookingStatsAPI.openedNotBooked).toHaveBeenCalledWith({
      period: 30,
      scope: 'mine',
      page: 1,
    });
    const item = wrapper.get('[data-row="7"]');
    expect(item.text()).toContain('Paula Reis');
    expect(item.text()).toContain('BOOKING.RESULTS.LIST.OPENED');
    expect(item.text()).toContain('"page":"Conversa de 30 min"');
    expect(wrapper.text()).toContain('BOOKING.RESULTS.LIST.HINT_MINE');
  });

  it('não envia nada sozinho: só chama o reenvio no toque, e mostra "Enviado de novo"', async () => {
    BookingStatsAPI.resend.mockResolvedValue({
      data: { payload: { id: 7, resent_at: '2026-10-09T15:00:00Z' } },
    });
    const wrapper = mountList({}, { attachTo: document.body });
    await flushPromises();
    expect(BookingStatsAPI.resend).not.toHaveBeenCalled();

    const button = wrapper.get('[data-resend]');
    expect(button.attributes('aria-label')).toBe(
      'BOOKING.RESULTS.LIST.RESEND_LABEL {"name":"Paula Reis"}'
    );
    await button.trigger('click');
    await flushPromises();

    expect(BookingStatsAPI.resend).toHaveBeenCalledWith(7);
    expect(wrapper.get('[data-resent]').attributes('role')).toBe('status');
    expect(document.activeElement).toBe(wrapper.get('[data-resent]').element);
    expect(wrapper.find('[data-resend]').exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('BOOKING.RESULTS.LIST.SENT_OK');
    wrapper.unmount();
  });

  it('explica a janela fechada sem marcar como enviado', async () => {
    BookingStatsAPI.resend.mockRejectedValue({
      response: { status: 422, data: { error: 'crm.booking_v2.cannot_reply' } },
    });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.get('[data-resend]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-row-error]').text()).toBe(
      'BOOKING.RESULTS.LIST.ERRORS.CANNOT_REPLY'
    );
    expect(wrapper.find('[data-resent]').exists()).toBe(false);
  });

  it('diz que não pode enviar quando o servidor recusa a pessoa (401)', async () => {
    BookingStatsAPI.resend.mockRejectedValue({ response: { status: 401 } });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.get('[data-resend]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-row-error]').text()).toBe(
      'BOOKING.RESULTS.LIST.ERRORS.FORBIDDEN'
    );
  });

  it('sem conversa visível, não oferece o botão e diz o que fazer; já reenviado, mostra o estado', async () => {
    BookingStatsAPI.openedNotBooked.mockResolvedValue(
      listOf([
        row({ id: 8, can_resend: false }),
        row({ id: 9, resent_at: '2026-10-08T10:00:00Z' }),
      ])
    );
    const wrapper = mountList();
    await flushPromises();

    expect(wrapper.get('[data-row="8"]').find('[data-resend]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-row="8"] [data-no-conversation]').exists()).toBe(
      true
    );
    expect(wrapper.get('[data-row="9"] [data-resent]').exists()).toBe(true);
  });

  it('quem não pode mandar o link não vê "Enviar de novo" nem a dica do card', async () => {
    BookingStatsAPI.openedNotBooked.mockResolvedValue(
      listOf([row({ can_resend: false })], {
        page: 1,
        total: 1,
        can_resend: false,
      })
    );
    const wrapper = mountList({ scope: 'team' });
    await flushPromises();

    const item = wrapper.get('[data-row="7"]');
    expect(item.text()).toContain('Paula Reis');
    expect(item.find('[data-resend]').exists()).toBe(false);
    expect(item.find('[data-no-conversation]').exists()).toBe(false);
  });

  it('lista vazia: uma frase e um botão que pede os 30 dias', async () => {
    BookingStatsAPI.openedNotBooked.mockResolvedValue(listOf([]));
    const wrapper = mountList({ period: 7 });
    await flushPromises();

    const empty = wrapper.get('[data-list-empty]');
    expect(empty.findAll('p')).toHaveLength(1);
    expect(empty.findAll('button')).toHaveLength(1);
    await wrapper.get('[data-list-empty-action]').trigger('click');
    expect(wrapper.emitted('changePeriod')).toEqual([[30]]);
  });

  it('carrega a próxima página em "Ver mais" e some quando acabou', async () => {
    BookingStatsAPI.openedNotBooked
      .mockResolvedValueOnce(listOf([row()], { page: 1, total: 2 }))
      .mockResolvedValueOnce(
        listOf([row(), row({ id: 10 })], { page: 2, total: 2 })
      );
    const wrapper = mountList();
    await flushPromises();

    await wrapper.get('[data-list-more]').trigger('click');
    await flushPromises();

    expect(BookingStatsAPI.openedNotBooked).toHaveBeenLastCalledWith({
      period: 30,
      scope: 'mine',
      page: 2,
    });
    expect(wrapper.findAll('[data-row]')).toHaveLength(2);
    expect(wrapper.find('[data-list-more]').exists()).toBe(false);
  });

  it('busca de novo quando o período ou o escopo mudam', async () => {
    const wrapper = mountList();
    await flushPromises();
    await wrapper.setProps({ scope: 'team' });
    await flushPromises();

    expect(BookingStatsAPI.openedNotBooked).toHaveBeenLastCalledWith({
      period: 30,
      scope: 'team',
      page: 1,
    });
    expect(wrapper.text()).toContain('BOOKING.RESULTS.LIST.HINT_TEAM');
  });
});
