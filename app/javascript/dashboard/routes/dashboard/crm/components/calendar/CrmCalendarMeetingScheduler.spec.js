import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../vitest.i18n';
import CrmCalendarMeetingScheduler from './CrmCalendarMeetingScheduler.vue';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';

// Janela "Agendar reunião" (#1265): marca pela agenda do agendamento novo (A),
// mantém o caminho do Google/Microsoft numa aba, manda o link para o cliente
// escolher (B) e, sem página nem caixa, leva à tela de páginas (C).
withFullI18n('pt_BR');

const store = { getters: {} };
const router = { hasRoute: vi.fn(() => true), push: vi.fn() };

vi.mock('vuex', () => ({ useStore: () => store }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => router,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: {
    getAvailability: vi.fn(() => Promise.resolve({ data: { payload: {} } })),
  },
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { bookable: vi.fn(), slots: vi.fn(), book: vi.fn() },
}));
vi.mock('dashboard/api/crmBookingInvites', () => ({
  default: { create: vi.fn(), deliver: vi.fn(), copied: vi.fn() },
}));

const PAGE = {
  id: 3,
  title: 'Conversa de 30 min',
  timezone: 'America/Sao_Paulo',
  duration_minutes: 30,
  durations: [30],
  notices: true,
  locations: [
    { type: 'whatsapp_video', label: 'Vídeo no WhatsApp', needs_email: false },
  ],
};
const SLOT = '2099-10-20T10:00:00-03:00';
const GOOGLE_INBOX = { id: 9, calendar_enabled: true, provider: 'google' };
const CARD = {
  id: 7,
  title: 'Marcos - Agendamento',
  contact: { name: 'Marcos' },
  conversation: { display_id: 44 },
};

const setStore = ({ flag = true, role = 'administrator' } = {}) => {
  store.getters = {
    getCurrentRole: role,
    getCurrentUser: { accounts: [{ id: 1, permissions: [] }] },
    'accounts/getAccount': () => ({ features: { crm_booking_v2: flag } }),
  };
};

const mountScheduler = (props = {}) =>
  mount(CrmCalendarMeetingScheduler, {
    props: {
      show: false,
      accountId: 1,
      cardId: 7,
      card: CARD,
      date: '2099-10-20',
      ...props,
    },
    attachTo: document.body,
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });

const open = async wrapper => {
  await wrapper.setProps({ show: true });
  await flushPromises();
};

describe('CrmCalendarMeetingScheduler', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    setStore();
    crmBookingPagesAPI.bookable.mockResolvedValue({
      data: { payload: [PAGE] },
    });
    crmBookingPagesAPI.slots.mockResolvedValue({
      data: { payload: { slots: [SLOT], next_slot: null } },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('A: with a published page and no Google, books by the agenda', async () => {
    crmBookingPagesAPI.book.mockResolvedValue({
      data: { payload: { id: 50, source: 'panel' } },
    });
    const wrapper = mountScheduler();
    await open(wrapper);

    expect(wrapper.find('[data-booking-agenda]').exists()).toBe(true);
    expect(wrapper.find('[data-scheduler-tabs]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Nenhuma caixa de entrada');
    expect(crmBookingPagesAPI.slots).toHaveBeenCalledWith(3, {
      date: '2099-10-20',
      duration: 30,
    });
    expect(wrapper.get('[data-booking-agenda-notify]').element.checked).toBe(
      true
    );
    expect(wrapper.get('[data-booking-agenda-notify-when]').text()).toBe(
      'Use quando o cliente combinou o horário com você.'
    );

    await wrapper.get('[data-booking-agenda-slots] button').trigger('click');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(crmBookingPagesAPI.book).toHaveBeenCalledWith(
      3,
      expect.objectContaining({
        cardId: 7,
        startsAt: SLOT,
        duration: 30,
        location: 'whatsapp_video',
        notify: true,
      })
    );
    expect(wrapper.emitted('create')[0][0]).toEqual({
      id: 50,
      source: 'panel',
    });
  });

  it('A: a taken time shows the message and reloads the times', async () => {
    crmBookingPagesAPI.book.mockRejectedValue({
      response: {
        status: 409,
        data: { error: 'crm.booking_v2.slot_unavailable' },
      },
    });
    const wrapper = mountScheduler();
    await open(wrapper);
    await wrapper.get('[data-booking-agenda-slots] button').trigger('click');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(wrapper.text()).toContain('Esse horário acabou de ser ocupado');
    expect(crmBookingPagesAPI.slots).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('create')).toBeUndefined();
  });

  it('keeps the Google/Microsoft path in its own tab', async () => {
    const wrapper = mountScheduler({ availableInboxes: [GOOGLE_INBOX] });
    await open(wrapper);

    expect(wrapper.find('[data-scheduler-tabs]').exists()).toBe(true);
    expect(wrapper.find('[data-booking-agenda]').exists()).toBe(true);

    await wrapper.get('[data-scheduler-tab="provider"]').trigger('click');

    expect(wrapper.find('[data-booking-agenda]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Enviar de');
  });

  it('without the account flag, the window is the old one', async () => {
    setStore({ flag: false });
    const wrapper = mountScheduler({ availableInboxes: [GOOGLE_INBOX] });
    await open(wrapper);

    expect(crmBookingPagesAPI.bookable).not.toHaveBeenCalled();
    expect(wrapper.find('[data-scheduler-tabs]').exists()).toBe(false);
    expect(wrapper.find('[data-booking-agenda]').exists()).toBe(false);
  });

  it('C: without page and without Google, leads to the pages screen', async () => {
    crmBookingPagesAPI.bookable.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountScheduler();
    await open(wrapper);

    const empty = wrapper.get('[data-booking-agenda-empty]');
    expect(empty.text()).toContain('Crie sua página de agendamento');
    await wrapper.get('[data-booking-agenda-open-settings]').trigger('click');

    expect(router.push).toHaveBeenCalledWith({
      name: 'settings_booking',
      params: { accountId: 1 },
    });
  });

  it('a failed load shows the error with retry, never the create-page state', async () => {
    crmBookingPagesAPI.bookable.mockRejectedValueOnce({
      response: { status: 500 },
    });
    const wrapper = mountScheduler();
    await open(wrapper);

    expect(wrapper.find('[data-booking-agenda-load-error]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-booking-agenda-empty]').exists()).toBe(false);

    await wrapper
      .get('[data-booking-agenda-load-error] button')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-booking-agenda]').exists()).toBe(true);
  });

  it('C: an agent without access to the pages sees who to ask, no button', async () => {
    setStore({ role: 'agent' });
    crmBookingPagesAPI.bookable.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountScheduler();
    await open(wrapper);

    expect(wrapper.text()).toContain('Peça ao administrador');
    expect(wrapper.find('[data-booking-agenda-open-settings]').exists()).toBe(
      false
    );
  });

  it('B: sends the link for the client to choose in the conversation', async () => {
    BookingInvitesAPI.create.mockResolvedValue({
      data: {
        payload: {
          id: 5,
          url: 'https://x.test/b/abc',
          text: 'Oi, Marcos! https://x.test/b/abc',
        },
      },
    });
    BookingInvitesAPI.deliver.mockResolvedValue({ data: { payload: {} } });
    const wrapper = mountScheduler();
    await open(wrapper);

    await wrapper.get('[data-booking-agenda-send-link]').trigger('click');
    await flushPromises();

    expect(BookingInvitesAPI.create).toHaveBeenCalledWith({
      bookingPageId: 3,
      cardId: 7,
    });
    expect(wrapper.text()).toContain('Oi, Marcos! https://x.test/b/abc');
    expect(wrapper.find('[data-booking-agenda-save]').exists()).toBe(false);

    await wrapper.get('[data-booking-agenda-link-send]').trigger('click');
    await flushPromises();

    expect(BookingInvitesAPI.deliver).toHaveBeenCalledWith(5, {
      conversationId: 44,
      text: 'Oi, Marcos! https://x.test/b/abc',
    });
  });
});
