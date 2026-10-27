import { mount, flushPromises } from '@vue/test-utils';
import WhatsappHybridPage from '../WhatsappHybridPage.vue';
import WhatsappHybridAPI from 'dashboard/api/whatsappHybrid';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/whatsappHybrid', () => ({
  default: {
    show: vi.fn(),
    pause: vi.fn(),
    resume: vi.fn(),
    connect: vi.fn(),
    reconnect: vi.fn(),
    disconnect: vi.fn(),
    updateSettings: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Conta em Tóquio: as datas da aba seguem o fuso da conta, não o do navegador (o do teste).
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return {
    useAccount: () => ({ currentAccount: ref({ timezone: 'Asia/Tokyo' }) }),
  };
});

vi.mock('qrcode', () => ({
  default: { toDataURL: vi.fn(async value => `data:image/png;${value}`) },
}));

const translate = (key, params) => {
  if (params?.inbox) return `${key}|${params.inbox}`;
  if (params?.phone) return `${key}|${params.phone}`;
  if (params?.end) return `${key}|${params.end}`;
  return key;
};

vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return { useI18n: () => ({ t: translate, locale: ref('pt_BR') }) };
});

const KEY = 'INBOX_MGMT.WHATSAPP_HYBRID';

const ButtonStub = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

// O diálogo de confirmação: só mostra o texto e o botão de confirmar depois de aberto, como o real.
const DialogStub = {
  props: ['title', 'description', 'confirmButtonLabel'],
  emits: ['confirm'],
  data: () => ({ opened: false }),
  methods: {
    open() {
      this.opened = true;
    },
    close() {
      this.opened = false;
    },
  },
  template:
    '<div v-if="opened" data-test="dialog"><p>{{ description }}</p><button data-test="dialog-confirm" @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
};

const mountPage = () =>
  mount(WhatsappHybridPage, {
    props: { inbox: { id: 7 } },
    global: {
      mocks: { $t: translate },
      stubs: {
        Button: ButtonStub,
        Dialog: DialogStub,
        SidePanel: true,
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
const pausedState = {
  ...connected,
  status: 'disconnected',
  connected: false,
  paused: true,
};

const buttonWith = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text() === label);

describe('WhatsappHybridPage (chat#1487, gold standard)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('shows the dark hero with the connection chip', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: connected });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-hybrid-heroi]').text()).toContain(
      `${KEY}.HERO.TITLE`
    );
    expect(wrapper.find('[data-hybrid-selo]').text()).toBe(
      `${KEY}.STATUS.CONNECTED`
    );
    expect(wrapper.find('[data-situacao]').attributes('data-phase')).toBe(
      'connected'
    );
  });

  it('opens the confirmation when Pause is clicked and only pauses on confirm', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: connected });
    WhatsappHybridAPI.pause.mockResolvedValue({ data: pausedState });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-test="dialog"]').exists()).toBe(false);
    await buttonWith(wrapper, `${KEY}.PAUSE.BUTTON`).trigger('click');

    const dialog = wrapper.find('[data-test="dialog"]');
    expect(dialog.text()).toContain(`${KEY}.PAUSE.CONFIRM_TEXT`);
    expect(WhatsappHybridAPI.pause).not.toHaveBeenCalled();

    await dialog.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(WhatsappHybridAPI.pause).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-hybrid-selo]').text()).toBe(
      `${KEY}.STATUS.PAUSED`
    );
    expect(wrapper.text()).toContain(`${KEY}.PAUSE.PAUSED_TITLE`);
    expect(wrapper.text()).not.toContain(`${KEY}.PAUSE.BUTTON`);
  });

  it('shows only Resume while paused, not the reconnect flow', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: pausedState });
    WhatsappHybridAPI.resume.mockResolvedValue({ data: connected });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-reconnect]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(`${KEY}.DISCONNECTED_HELP`);
    await buttonWith(wrapper, `${KEY}.PAUSE.RESUME`).trigger('click');
    await flushPromises();

    expect(WhatsappHybridAPI.resume).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-hybrid-selo]').text()).toBe(
      `${KEY}.STATUS.CONNECTED`
    );
  });

  it('falls into the QR flow when resuming needs a new pairing', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: pausedState });
    WhatsappHybridAPI.resume.mockResolvedValue({
      data: {
        ...pausedState,
        status: 'awaiting_scan',
        paused: false,
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

  it('asks before disconnecting, because it unlinks the phone', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({ data: connected });
    WhatsappHybridAPI.disconnect.mockResolvedValue({});
    const wrapper = mountPage();
    await flushPromises();

    await buttonWith(wrapper, `${KEY}.DISCONNECT`).trigger('click');
    expect(WhatsappHybridAPI.disconnect).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(`${KEY}.DISCONNECT_CONFIRM.TEXT`);

    const confirm = wrapper
      .findAll('[data-test="dialog-confirm"]')
      .find(button => button.text() === `${KEY}.DISCONNECT_CONFIRM.CONFIRM`);
    await confirm.trigger('click');
    await flushPromises();

    expect(WhatsappHybridAPI.disconnect).toHaveBeenCalledWith(7);
  });

  it('keeps one main action for a stopped connection: a new QR code', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, status: 'failed', connected: false },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-situacao]').attributes('data-phase')).toBe(
      'stopped'
    );
    expect(wrapper.text()).toContain(`${KEY}.REMOVED_TITLE`);
    expect(wrapper.find('[data-reconnect]').exists()).toBe(true);
    expect(wrapper.find('[data-pause]').exists()).toBe(false);
  });

  it('asks to try again in a few seconds while a paused session is starting again', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, status: 'failed', connected: false },
    });
    WhatsappHybridAPI.reconnect.mockRejectedValue({
      response: { data: { error: 'waking' } },
    });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-reconnect]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.ERRORS.WAKING`);
  });

  it('warns about a wrong phone and hides risk, routing and pause', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, same_number: false },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain(`${KEY}.STATE.WRONG_NUMBER_TITLE`);
    expect(wrapper.find('[data-hybrid-risk]').exists()).toBe(false);
    expect(wrapper.find('[data-hybrid-routing]').exists()).toBe(false);
    expect(wrapper.find('[data-pause]').exists()).toBe(false);
  });

  it('shows the WhatsApp restriction (#1480/#1481) when connected', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, timelock: { active: true } },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-hybrid-timelock]').text()).toContain(
      `${KEY}.TIMELOCK.NO_END`
    );
  });

  it('writes the restriction end in the account time zone', async () => {
    // 2026-10-14 02:30 UTC = 14/10 11:30 em Tóquio.
    const endsAt = Date.UTC(2026, 9, 14, 2, 30) / 1000;
    vi.setSystemTime(Date.UTC(2026, 9, 13, 20, 0));
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, timelock: { active: true, ends_at: endsAt } },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-hybrid-timelock]').text()).toBe(
      `${KEY}.TIMELOCK.UNTIL|14/10, 11:30`
    );
  });

  it('shows the connected phone formatted, not raw digits', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, phone: '551140001487' },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-situacao]').text()).toContain(
      `${KEY}.CONNECTED_HELP|+55 11 4000-1487`
    );
  });

  it('says the QR expired in the chip, like the title', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: { ...connected, status: 'failed', connected: false, phone: null },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-hybrid-selo]').text()).toBe(
      `${KEY}.STATUS.EXPIRED`
    );
  });

  it('hides "use a code instead" once the code is on screen', async () => {
    WhatsappHybridAPI.show.mockResolvedValue({
      data: {
        ...connected,
        status: 'awaiting_scan',
        connected: false,
        qr: 'q',
      },
    });
    WhatsappHybridAPI.requestCode = vi.fn().mockResolvedValue({
      data: { code: 'ABCD-1234' },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-use-code]').exists()).toBe(true);
    await wrapper.find('[data-use-code]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-pairing-code]').text()).toBe('ABCD-1234');
    expect(wrapper.find('[data-use-code]').exists()).toBe(false);
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
    WhatsappHybridAPI.connect.mockResolvedValue({
      data: {
        ...connected,
        status: 'awaiting_scan',
        connected: false,
        qr: 'q',
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-test="same-number"]').text()).toContain(
      `${KEY}.NOTICES.SAME_NUMBER|Vendas WhatsApp`
    );
    expect(wrapper.find('[data-test="app-reminder"]').exists()).toBe(false);
    expect(wrapper.find('[data-hybrid-more]').exists()).toBe(false);
    const order = wrapper
      .findAll('[data-connect-order] li')
      .map(item => item.text());
    expect(order).toEqual([
      `1 ${KEY}.CONNECT_ORDER.STEP_1`,
      `2 ${KEY}.CONNECT_ORDER.STEP_2`,
      `3 ${KEY}.CONNECT_ORDER.STEP_3`,
    ]);

    await buttonWith(wrapper, `${KEY}.CONNECT`).trigger('click');
    await flushPromises();
    expect(WhatsappHybridAPI.connect).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain(`${KEY}.SCAN_TITLE`);
  });

  it('says it could not open the tab and offers to try again', async () => {
    WhatsappHybridAPI.show.mockRejectedValueOnce(new Error('down'));
    WhatsappHybridAPI.show.mockResolvedValueOnce({ data: connected });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-hybrid-error]').attributes('role')).toBe(
      'alert'
    );
    await buttonWith(wrapper, `${KEY}.RETRY`).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-situacao]').attributes('data-phase')).toBe(
      'connected'
    );
  });
});
