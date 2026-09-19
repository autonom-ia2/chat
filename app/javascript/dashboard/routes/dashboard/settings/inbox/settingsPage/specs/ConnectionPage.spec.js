import { mount, flushPromises } from '@vue/test-utils';
import ConnectionPage from '../ConnectionPage.vue';
import WahaInboxAPI from 'dashboard/api/wahaInbox';

vi.mock('dashboard/api/wahaInbox', () => ({
  default: { connection: vi.fn(), reconnect: vi.fn() },
}));

vi.mock('qrcode', () => ({
  default: { toDataURL: vi.fn(async value => `data:image/png;${value}`) },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}|${params.time}` : key),
  }),
}));

const KEY = 'INBOX_MGMT.WAHA_CONNECTION';

const mountPage = () =>
  mount(ConnectionPage, {
    props: { inbox: { id: 7, name: 'Comercial' } },
    global: {
      stubs: {
        NextButton: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const connectionReturns = data =>
  WahaInboxAPI.connection.mockResolvedValue({ data });

describe('ConnectionPage (WhatsApp via QR)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('shows the QR with the time left to scan', async () => {
    connectionReturns({ status: 'awaiting_scan', phone: '', qr: 'code-1' });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('img').attributes('src')).toContain('code-1');
    expect(wrapper.text()).toContain(`${KEY}.TIME_LEFT|2:40`);
    expect(wrapper.text()).not.toContain(`${KEY}.EXPIRED_TITLE`);
  });

  it('counts the next QR as a later code in the pairing window', async () => {
    connectionReturns({ status: 'awaiting_scan', phone: '', qr: 'code-1' });
    const wrapper = mountPage();
    await flushPromises();

    connectionReturns({ status: 'awaiting_scan', phone: '', qr: 'code-2' });
    await vi.advanceTimersByTimeAsync(3000);

    expect(wrapper.find('img').attributes('src')).toContain('code-2');
    expect(wrapper.text()).toContain(`${KEY}.TIME_LEFT|1:40`);
  });

  it('replaces the endless spinner with an expired state and a clear action', async () => {
    connectionReturns({ status: 'failed', phone: '', qr: null });
    WahaInboxAPI.reconnect.mockResolvedValue({
      data: { status: 'connecting' },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain(`${KEY}.EXPIRED_TITLE`);
    expect(wrapper.find('img').exists()).toBe(false);

    const buttons = wrapper.findAll('button');
    expect(buttons).toHaveLength(1);
    await buttons[0].trigger('click');
    await flushPromises();

    expect(WahaInboxAPI.reconnect).toHaveBeenCalledWith(7);
  });

  it('shows the connected state without QR or reconnect button', async () => {
    connectionReturns({ status: 'connected', phone: '5511', qr: null });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain(`${KEY}.CONNECTED_HELP`);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(0);
  });
});
