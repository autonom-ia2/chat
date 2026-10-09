// O literal "javascript:" é o dado de ataque que estes testes precisam recusar.
/* eslint-disable no-script-url */
import { mount, flushPromises } from '@vue/test-utils';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CrmMeetingDetail from './CrmMeetingDetail.vue';

vi.mock('dashboard/api/crmMeetings', () => ({
  default: { show: vi.fn(), sync: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const LOCATION = 'CRM_KANBAN.CALENDAR.MEETING_LOCATION';

const meeting = (extra = {}) => ({
  id: 7,
  title: 'Conversa com a cliente',
  status: 'scheduled',
  starts_at: '2026-10-15T14:00:00Z',
  ends_at: '2026-10-15T14:30:00Z',
  timezone: 'UTC',
  guests: [],
  ...extra,
});

const mountDetail = async event => {
  crmMeetingsAPI.sync.mockResolvedValue({ data: { payload: event } });
  crmMeetingsAPI.show.mockResolvedValue({ data: { payload: event } });
  const wrapper = mount(CrmMeetingDetail, {
    props: { show: true, event, accountId: 1, timezone: 'UTC' },
    global: {
      stubs: {
        Dialog: true,
        Spinner: true,
        Button: { template: '<button><slot /></button>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const joinButton = wrapper =>
  wrapper.find(
    'button[aria-label="CRM_KANBAN.CALENDAR.MEETING_DETAIL.JOIN_MEETING"]'
  );
const headerIcon = wrapper =>
  wrapper.find('header span span[aria-hidden="true"]');

describe('CrmMeetingDetail: local da reunião', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => vi.restoreAllMocks());

  it.each([
    ['whatsapp_video', 'WHATSAPP_VIDEO', 'i-lucide-video'],
    ['whatsapp_voice', 'WHATSAPP_VOICE', 'i-lucide-phone'],
    ['in_person', 'IN_PERSON', 'i-lucide-map-pin'],
  ])(
    'reunião interna %s mostra o local, sem ícone do Google nem botão de entrar',
    async (type, labelKey, icon) => {
      const wrapper = await mountDetail(
        meeting({ provider: 'internal', online_meeting_type: type })
      );

      expect(wrapper.find('[data-test="meeting-location"]').text()).toContain(
        `${LOCATION}.${labelKey}`
      );
      expect(headerIcon(wrapper).classes()).toContain(icon);
      expect(wrapper.html()).not.toContain('i-logos-');
      expect(joinButton(wrapper).exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it('link do agente com https mostra o botão e abre o endereço', async () => {
    const wrapper = await mountDetail(
      meeting({
        provider: 'internal',
        online_meeting_type: 'custom_link',
        online_meeting_url: 'https://sala.exemplo.com/1',
      })
    );

    expect(wrapper.find('[data-test="meeting-location"]').text()).toContain(
      `${LOCATION}.CUSTOM_LINK`
    );
    expect(wrapper.html()).not.toContain('i-logos-');
    await joinButton(wrapper).trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      'https://sala.exemplo.com/1',
      '_blank',
      'noopener,noreferrer'
    );
    wrapper.unmount();
  });

  it('link do agente com javascript: não vira botão e nunca é aberto', async () => {
    const wrapper = await mountDetail(
      meeting({
        provider: 'internal',
        online_meeting_type: 'custom_link',
        online_meeting_url: 'javascript:alert(1)',
      })
    );

    expect(joinButton(wrapper).exists()).toBe(false);
    expect(wrapper.html()).not.toContain('javascript:');
    expect(window.open).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('Google segue igual: ícone e botão do Meet, sem linha de local nova', async () => {
    const url = 'https://meet.google.com/abc-defg';
    const wrapper = await mountDetail(
      meeting({
        provider: 'google',
        online_meeting_type: 'google_meet',
        online_meeting_url: url,
      })
    );

    expect(wrapper.find('[data-test="meeting-location"]').exists()).toBe(false);
    expect(headerIcon(wrapper).classes()).toContain('i-logos-google-icon');
    expect(joinButton(wrapper).find('span').classes()).toContain(
      'i-logos-google-meet'
    );
    expect(joinButton(wrapper).classes()).toContain('bg-[#00897b]');
    await joinButton(wrapper).trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      url,
      '_blank',
      'noopener,noreferrer'
    );
    wrapper.unmount();
  });

  it('Microsoft segue igual: ícone e botão do Teams, sem linha de local nova', async () => {
    const url = 'https://teams.microsoft.com/l/meetup-join/x';
    const wrapper = await mountDetail(
      meeting({
        provider: 'microsoft',
        online_meeting_type: 'teams',
        online_meeting_url: url,
      })
    );

    expect(wrapper.find('[data-test="meeting-location"]').exists()).toBe(false);
    expect(headerIcon(wrapper).classes()).toContain('i-logos-microsoft-icon');
    expect(joinButton(wrapper).find('span').classes()).toContain(
      'i-logos-microsoft-teams'
    );
    expect(joinButton(wrapper).classes()).toContain('bg-[#6264a7]');
    await joinButton(wrapper).trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      url,
      '_blank',
      'noopener,noreferrer'
    );
    wrapper.unmount();
  });
});

describe('CrmMeetingDetail: resposta do cliente e avisos (#1192)', () => {
  const BASE = 'CRM_KANBAN.CALENDAR.MEETING_DETAIL';

  beforeEach(() => vi.clearAllMocks());

  it('reunião comum, sem avisos nem resposta, não ganha o selo', async () => {
    const wrapper = await mountDetail(
      meeting({ confirmation_status: 'pending', notices: [] })
    );
    expect(wrapper.find('[data-test="meeting-client-reply"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });

  it.each([
    ['confirmed', 'CONFIRMED'],
    ['change_requested', 'CHANGE_REQUESTED'],
  ])('cliente %s aparece com selo discreto', async (status, key) => {
    const wrapper = await mountDetail(
      meeting({ confirmation_status: status, notices: [] })
    );
    const badge = wrapper.find('[data-test="meeting-confirmation"]');
    expect(badge.attributes('data-status')).toBe(status);
    expect(badge.text()).toBe(`${BASE}.CLIENT.${key}`);
    wrapper.unmount();
  });

  it('lista os avisos com motivo leigo e diz quem parou de receber', async () => {
    const wrapper = await mountDetail(
      meeting({
        confirmation_status: 'pending',
        notices_stopped: true,
        notices: [
          {
            kind: 'booked',
            due_at: '2026-10-14T10:00:00Z',
            status: 'sent',
            skip_reason: null,
          },
          {
            kind: 'day_before',
            due_at: '2026-10-14T14:00:00Z',
            status: 'skipped',
            skip_reason: 'waha_outside_window',
          },
          {
            kind: 'hour_before',
            due_at: '2026-10-15T13:00:00Z',
            status: 'failed',
            skip_reason: null,
          },
        ],
      })
    );
    expect(wrapper.find('[data-test="meeting-confirmation"]').text()).toBe(
      `${BASE}.CLIENT.PENDING`
    );
    expect(wrapper.find('[data-test="meeting-notices-stopped"]').text()).toBe(
      `${BASE}.CLIENT.STOPPED`
    );
    const items = wrapper.findAll('[data-notice]');
    expect(items.map(item => item.attributes('data-notice'))).toEqual([
      'booked',
      'day_before',
      'hour_before',
    ]);
    expect(items[0].text()).toContain(`${BASE}.NOTICES.STATUS.SENT`);
    expect(items[1].text()).toContain(
      `${BASE}.NOTICES.SKIP_REASONS.WAHA_OUTSIDE_WINDOW`
    );
    expect(items[2].text()).toContain(`${BASE}.NOTICES.STATUS.FAILED`);
    expect(wrapper.find('[data-test="meeting-notice-failed"]').exists()).toBe(
      true
    );
    wrapper.unmount();
  });

  it('motivo desconhecido cai em "outro motivo"', async () => {
    const wrapper = await mountDetail(
      meeting({
        notices: [
          {
            kind: 'booked',
            due_at: '2026-10-14T10:00:00Z',
            status: 'skipped',
            skip_reason: 'novo_motivo',
          },
        ],
      })
    );
    expect(wrapper.find('[data-notice="booked"]').text()).toContain(
      `${BASE}.NOTICES.SKIP_REASONS.OTHER`
    );
    wrapper.unmount();
  });
});
