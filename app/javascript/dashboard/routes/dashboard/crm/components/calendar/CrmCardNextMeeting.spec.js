import { mount, flushPromises } from '@vue/test-utils';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CrmCardNextMeeting from './CrmCardNextMeeting.vue';

// A próxima reunião no card (#1193, J4-A1/A5): horário, local, número e a
// resposta do cliente, com "Chamar no WhatsApp" e "Lembrar".
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '3' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: { index: vi.fn(), show: vi.fn(), remind: vi.fn() },
}));

const FUTURE = new Date(Date.now() + 86400000).toISOString();
const detail = {
  id: 11,
  card_id: 8,
  title: 'Conversa de 30 min',
  status: 'scheduled',
  starts_at: FUTURE,
  provider: 'internal',
  online_meeting_type: 'whatsapp_video',
  location_type: 'whatsapp_video',
  booking: true,
  confirmation_status: 'pending',
  notices_stopped: false,
  client: {
    name: 'Ana',
    phone: '+5511988887777',
    whatsapp_url: 'https://wa.me/5511988887777',
    conversation_id: 4,
  },
};

describe('CrmCardNextMeeting', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads the next scheduled meeting of the card and shows time, location, number, status and actions', async () => {
    crmMeetingsAPI.index.mockResolvedValue({ data: { payload: [{ id: 11 }] } });
    crmMeetingsAPI.show.mockResolvedValue({ data: { payload: detail } });

    const wrapper = mount(CrmCardNextMeeting, { props: { cardId: 8 } });
    await flushPromises();

    const [account, params] = crmMeetingsAPI.index.mock.calls[0];
    expect(account).toBe('3');
    expect(params).toMatchObject({
      card_id: 8,
      status: 'scheduled',
      per_page: 1,
    });
    expect(Number.isNaN(Date.parse(params.from))).toBe(false);
    expect(crmMeetingsAPI.show).toHaveBeenCalledWith('3', 11);
    const box = wrapper.find('[data-test="card-next-meeting"]');
    expect(box.text()).toContain(
      'CRM_KANBAN.CALENDAR.MEETING_LOCATION.WHATSAPP_VIDEO'
    );
    expect(box.text()).toContain('+55 11 98888 7777');
    expect(wrapper.find('[data-test="card-next-meeting-status"]').text()).toBe(
      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.PENDING'
    );
    expect(wrapper.find('[data-test="meeting-call-button"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test="meeting-remind-button"]').exists()).toBe(
      true
    );
  });

  it('shows nothing without a scheduled meeting or when loading fails', async () => {
    crmMeetingsAPI.index.mockResolvedValue({ data: { payload: [] } });
    const empty = mount(CrmCardNextMeeting, { props: { cardId: 8 } });
    await flushPromises();
    expect(empty.find('[data-test="card-next-meeting"]').exists()).toBe(false);
    expect(crmMeetingsAPI.show).not.toHaveBeenCalled();

    crmMeetingsAPI.index.mockRejectedValue(new Error('404'));
    const failed = mount(CrmCardNextMeeting, { props: { cardId: 9 } });
    await flushPromises();
    expect(failed.html()).toBe('<!--v-if-->');
  });
});
