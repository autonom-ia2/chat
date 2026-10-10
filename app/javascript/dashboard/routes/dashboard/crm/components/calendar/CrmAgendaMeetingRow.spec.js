import { mount, flushPromises } from '@vue/test-utils';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CrmCalendarAgenda from './CrmCalendarAgenda.vue';

// Agenda de hoje (#1193): a reunião de hoje mostra hora, local e a resposta do
// cliente; sem resposta, o "Lembrar" fica ao lado, sem abrir o detalhe.
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/crmMeetings', () => ({ default: { remind: vi.fn() } }));

// Relógio fixo ao meio-dia: as reuniões das 15:00 são "hoje" e ainda vão começar.
const NOON = new Date(2026, 9, 19, 12, 0);
const AT_THREE = new Date(2026, 9, 19, 15, 0);
const AT_HALF_PAST = new Date(2026, 9, 19, 15, 30);

const event = (id, extra = {}) => ({
  id: `meeting_${id}`,
  event_type: 'meeting',
  title: `Reunião ${id}`,
  starts_at: AT_THREE.toISOString(),
  ends_at: AT_HALF_PAST.toISOString(),
  status: 'scheduled',
  provider: 'internal',
  online_meeting_type: 'whatsapp_video',
  booking: true,
  confirmation_status: 'pending',
  notices_stopped: false,
  ...extra,
});

const mountAgenda = events =>
  mount(CrmCalendarAgenda, {
    props: { events },
    global: { stubs: { Spinner: true, Button: true } },
  });

const rows = wrapper => wrapper.findAll('[data-test="agenda-meeting"]');

describe('CrmCalendarAgenda: reuniões de hoje', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOON);
  });

  afterEach(() => vi.useRealTimers());

  it('shows location and client status for each meeting of today', () => {
    const wrapper = mountAgenda([
      event(1, { confirmation_status: 'confirmed' }),
      event(2, { confirmation_status: 'change_requested' }),
      event(3),
    ]);

    expect(rows(wrapper)).toHaveLength(3);
    const statuses = wrapper
      .findAll('[data-test="agenda-meeting-status"]')
      .map(item => item.text());
    expect(statuses).toEqual([
      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.CONFIRMED',
      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.CHANGE_REQUESTED',
      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.PENDING',
    ]);
    expect(rows(wrapper)[0].text()).toContain(
      'CRM_KANBAN.CALENDAR.MEETING_LOCATION.WHATSAPP_VIDEO'
    );
  });

  it('offers "Lembrar" only to meetings without confirmation, and sends on tap', async () => {
    crmMeetingsAPI.remind.mockResolvedValue({ data: { payload: {} } });
    const wrapper = mountAgenda([
      event(1, { confirmation_status: 'confirmed' }),
      event(2),
      event(3, { notices_stopped: true }),
      event(4, { booking: false }),
    ]);

    const reminders = wrapper.findAll('[data-test="meeting-remind-button"]');
    expect(reminders).toHaveLength(1);
    expect(
      rows(wrapper)[1].find('[data-test="meeting-remind-button"]').exists()
    ).toBe(true);
    await reminders[0].trigger('click');
    await flushPromises();

    expect(crmMeetingsAPI.remind).toHaveBeenCalledWith('1', '2');
    expect(wrapper.emitted('eventClick')).toBeUndefined();
  });

  it('a manual meeting has no client status; tapping the row opens the detail', async () => {
    const manual = event(5, {
      booking: false,
      provider: 'google',
      online_meeting_type: 'google_meet',
    });
    const wrapper = mountAgenda([manual]);

    expect(wrapper.find('[data-test="agenda-meeting-status"]').exists()).toBe(
      false
    );
    await rows(wrapper)[0].find('button').trigger('click');

    expect(wrapper.emitted('eventClick')[0]).toEqual([manual]);
  });
});
