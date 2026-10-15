import { mount, flushPromises } from '@vue/test-utils';
import WhatsappHybridPage from '../WhatsappHybridPage.vue';
import WhatsappHybridAPI from 'dashboard/api/whatsappHybrid';

vi.mock('dashboard/api/whatsappHybrid', () => ({
  default: {
    show: vi.fn(),
    pause: vi.fn(),
    resume: vi.fn(),
    connect: vi.fn(),
    disconnect: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('qrcode', () => ({
  default: { toDataURL: vi.fn(async value => `data:image/png;${value}`) },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params?.inbox ? `${key}|${params.inbox}` : key),
  }),
}));

const KEY = 'INBOX_MGMT.WHATSAPP_HYBRID';

const ButtonStub = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

// O diálogo de confirmação: o botão "confirmar" emite confirm, como o real.
const DialogStub = {
  props: ['title', 'description', 'confirmButtonLabel'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div><p>{{ description }}</p><button data-test="dialog-confirm" @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
};

const mountPage = () =>
  mount(WhatsappHybridPage, {
    props: { inbox: { id: 7 } },
    global: {
      stubs: {
        NextButton: ButtonStub,
        Button: ButtonStub,
        Dialog: DialogStub,
        Switch: true,
        Checkbox: true,
      },
    },
  });

const connected = {
  available: true,
  status: 'connected',
  connected: true,
  paused: false,
  phone: '5511999993846',
  same_number: true,
  risk_accepted: true,
  same_number_inboxes: [],
};

const buttonWith = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text() === label);

describe('WhatsappHybridPage — pause and notices (chat#1487)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('pauses after the short confirmation that explains the effect', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: connected });
    WhatsappHybridAPI.pause.mockResolvedValue({
      data: {
        ...connected,
        status: 'disconnected',
        connected: false,
        paused: true,
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain(`${KEY}.PAUSE.CONFIRM_TEXT`);
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(WhatsappHybridAPI.pause).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain(`${KEY}.STATUS.PAUSED`);
    expect(wrapper.text()).toContain(`${KEY}.PAUSE.PAUSED_TITLE`);
    expect(wrapper.text()).not.toContain(`${KEY}.PAUSE.BUTTON`);
  });

  it('shows only Resume while paused, not the reconnect flow', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: {
        ...connected,
        status: 'disconnected',
        connected: false,
        paused: true,
      },
    });
    WhatsappHybridAPI.resume.mockResolvedValue({ data: connected });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).not.toContain(
      'INBOX_MGMT.WAHA_CONNECTION.RECONNECT'
    );
    expect(wrapper.text()).not.toContain(`${KEY}.DISCONNECTED_HELP`);
    await buttonWith(wrapper, `${KEY}.PAUSE.RESUME`).trigger('click');
    await flushPromises();

    expect(WhatsappHybridAPI.resume).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain(`${KEY}.STATUS.CONNECTED`);
  });

  it('falls into the QR flow when resuming needs a new pairing', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: {
        ...connected,
        status: 'disconnected',
        connected: false,
        paused: true,
      },
    });
    WhatsappHybridAPI.resume.mockResolvedValue({
      data: {
        ...connected,
        status: 'awaiting_scan',
        connected: false,
        qr: 'code-1',
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    await buttonWith(wrapper, `${KEY}.PAUSE.RESUME`).trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain(`${KEY}.SCAN_TITLE`);
    expect(wrapper.find('img').attributes('src')).toContain('code-1');
  });

  it('shows the 14-day reminder when connected or paused', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: connected });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-test="app-reminder"]').text()).toContain(
      `${KEY}.NOTICES.APP_EVERY_14_DAYS`
    );
  });

  it('warns about the same number in another WhatsApp API inbox, before connecting too', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: {
        available: true,
        status: 'not_connected',
        connected: false,
        same_number_inboxes: ['Vendas WhatsApp'],
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-test="same-number"]').text()).toContain(
      `${KEY}.NOTICES.SAME_NUMBER|Vendas WhatsApp`
    );
    expect(wrapper.find('[data-test="app-reminder"]').exists()).toBe(false);
    const order = wrapper.findAll('ol li').map(item => item.text());
    expect(order).toEqual([
      `${KEY}.CONNECT_ORDER.STEP_1`,
      `${KEY}.CONNECT_ORDER.STEP_2`,
      `${KEY}.CONNECT_ORDER.STEP_3`,
    ]);
  });
});
