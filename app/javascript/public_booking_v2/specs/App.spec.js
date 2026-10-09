import { config, flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { createI18n } from 'vue-i18n';
import App from '../App.vue';
import * as api from '../api';
import { DEFAULT_BRAND_COLOR } from '../helpers/brand';
import messages from '../i18n';

vi.mock('../api', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    getPage: vi.fn(),
    getSlots: vi.fn(),
    getNextSlot: vi.fn(),
    createBooking: vi.fn(),
    requestContact: vi.fn(),
    getInvite: vi.fn(),
    markInviteViewed: vi.fn(),
  };
});

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages }),
];

const CaptchaStub = defineComponent({
  name: 'CaptchaField',
  render: () => h('div', { 'data-testid': 'captcha' }),
});

// Montado em partes para o lint não confundir o teste com uso de `javascript:`.
const SCRIPT = ['java', 'script:'].join('');

const NEXT_SLOT = '2026-10-13T15:00:00-03:00';
const OTHER_SLOT = '2026-10-13T16:00:00-03:00';

const PAGE = {
  slug: 'conversa',
  paused: false,
  preview: false,
  title: 'Conversa de 30 min',
  description: '',
  agent_name: 'Camila',
  agent_photo_url: null,
  duration_minutes: 30,
  durations: [30],
  timezone: 'America/Sao_Paulo',
  booking_window_days: 7,
  brand: { color: '#0B7A5A', headline: '', logo_url: null, photo_url: null },
  locations: [{ type: 'whatsapp_video', requires_email: false }],
  contact_whatsapp_url: 'https://wa.me/5511999990000',
  form_token: 'form-token',
  captcha_site_key: null,
  notices_enabled: false,
};

const INVITE = {
  code: 'Xk4p9Q',
  page_slug: 'conversa',
  state: 'open',
  contact_first_name: 'Marcos',
  phone_masked: '(11) •••••-5678',
};

const BOOKED = {
  confirmed: true,
  starts_at: NEXT_SLOT,
  ends_at: '2026-10-13T15:30:00-03:00',
  timezone: 'America/Sao_Paulo',
  location: { type: 'whatsapp_video' },
  ics_url: '/public/api/v2/ics/tok',
  manage_url: 'https://chat.example.com/b/Xk4p9Q',
  contact_whatsapp_url: 'https://wa.me/5511999990000',
};

const setPath = path => window.history.replaceState({}, '', path);

const mountApp = async ({ page = PAGE, path = '/book/conversa' } = {}) => {
  setPath(path);
  api.getPage.mockResolvedValue(page);
  const wrapper = mount(App, {
    global: { stubs: { CaptchaField: CaptchaStub } },
  });
  await flushPromises();
  return wrapper;
};

const findAction = (wrapper, text) =>
  wrapper.findAll('button, a').find(node => node.text().includes(text));

const click = async (wrapper, text) => {
  const node = findAction(wrapper, text);
  if (!node) throw new Error(`No button "${text}" in:\n${wrapper.text()}`);
  await node.trigger('click');
  await flushPromises();
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

const fillPublicDetails = async (wrapper, digits = '11988880000') => {
  await wrapper.find('#booking-name').setValue('Ana Souza');
  await wrapper.find('#booking-phone').setValue(digits);
};

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-12T12:00:00Z'));
  api.getNextSlot.mockResolvedValue({ starts_at: NEXT_SLOT });
  api.getSlots.mockResolvedValue({
    date: '2026-10-13',
    slots: [NEXT_SLOT, OTHER_SLOT],
  });
  api.createBooking.mockResolvedValue(BOOKED);
  api.requestContact.mockResolvedValue({ requested: true });
  api.getInvite.mockResolvedValue(INVITE);
  api.markInviteViewed.mockResolvedValue(null);
});

afterEach(() => {
  vi.useRealTimers();
});

describe('public link /book/:slug', () => {
  it('books from the earliest shortcut: open → earliest → details → done', async () => {
    const wrapper = await mountApp();

    expect(api.getPage).toHaveBeenCalledWith('conversa', null);
    expect(api.getNextSlot).toHaveBeenCalledWith('conversa', 30);
    expect(wrapper.text()).toContain('Qual dia fica bom?');
    expect(wrapper.text()).toContain('Mais cedo:');

    await click(wrapper, 'Escolher este');
    expect(wrapper.text()).toContain('Seus dados');
    expect(wrapper.find('#booking-email').exists()).toBe(true);

    await fillPublicDetails(wrapper);
    expect(wrapper.find('#booking-phone').element.value).toBe(
      '(11) 98888-0000'
    );
    await submit(wrapper);

    expect(api.createBooking).toHaveBeenCalledTimes(1);
    const [slug, payload] = api.createBooking.mock.calls[0];
    expect(slug).toBe('conversa');
    expect(payload).toEqual({
      name: 'Ana Souza',
      phone: '+5511988880000',
      email: undefined,
      starts_at: NEXT_SLOT,
      duration: 30,
      location_type: 'whatsapp_video',
      invite_code: undefined,
      consent: {
        accepted: false,
        text_key: 'booking_v2.consent.whatsapp_notices',
      },
      company: '',
      form_token: 'form-token',
      captcha_token: undefined,
    });

    expect(wrapper.text()).toContain('Tudo certo, Ana!');
    const save = findAction(wrapper, 'Salvar na minha agenda');
    expect(save.attributes('href')).toBe(
      `${window.location.origin}/public/api/v2/ics/tok`
    );
    expect(save.attributes('download')).toBeDefined();
    expect(findAction(wrapper, 'Falar no WhatsApp').attributes('href')).toBe(
      'https://wa.me/5511999990000'
    );
    expect(findAction(wrapper, 'Entrar na reunião')).toBeUndefined();
  });

  it('books through day and time; only free times become buttons', async () => {
    const wrapper = await mountApp();

    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await flushPromises();
    expect(api.getSlots).toHaveBeenCalledWith('conversa', '2026-10-13', 30);
    expect(wrapper.text()).toContain('Qual horário?');

    const times = wrapper
      .findAll('ul button')
      .map(node => node.text())
      .sort();
    // TZ=UTC no teste: 15:00 e 16:00 de Brasília aparecem como 18:00 e 19:00.
    expect(times).toEqual(['18:00', '19:00']);

    await click(wrapper, '19:00');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].starts_at).toBe(OTHER_SLOT);
  });

  it('shows the page time zone when it differs from the client', async () => {
    const wrapper = await mountApp();
    expect(wrapper.text()).toContain('Horários no seu fuso');
    expect(wrapper.text()).toContain('A agenda é no fuso');
  });

  it('asks for the email when the location requires it (Google Meet)', async () => {
    const wrapper = await mountApp({
      page: {
        ...PAGE,
        locations: [{ type: 'google_meet', requires_email: true }],
      },
    });
    await click(wrapper, 'Escolher este');
    expect(wrapper.find('label[for="booking-email"]').text()).toBe(
      'Seu e-mail'
    );

    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'Escreva seu e-mail para receber o link da reunião.'
    );

    await wrapper.find('#booking-email').setValue('ana@exemplo.com');
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].email).toBe('ana@exemplo.com');
  });

  it('lets the client pick a location and a duration with big cards, never a select', async () => {
    const wrapper = await mountApp({
      page: {
        ...PAGE,
        durations: [30, 60],
        locations: [
          { type: 'whatsapp_video', requires_email: false },
          { type: 'in_person', requires_email: false },
        ],
      },
    });
    expect(wrapper.find('select').exists()).toBe(false);
    await wrapper.find('input[name="booking-duration"][value="60"]').setValue();
    await flushPromises();
    expect(api.getNextSlot).toHaveBeenLastCalledWith('conversa', 60);

    await click(wrapper, 'Escolher este');
    await wrapper
      .find('input[name="booking-location"][value="in_person"]')
      .setValue();
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    const payload = api.createBooking.mock.calls[0][1];
    expect(payload.location_type).toBe('in_person');
    expect(payload.duration).toBe(60);
  });

  it('blocks a short number before calling the server', async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Escolher este');
    await fillPublicDetails(wrapper, '1198');
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
    expect(wrapper.find('#booking-phone').attributes('aria-invalid')).toBe(
      'true'
    );
  });
});

describe('server errors', () => {
  const failWith = code =>
    api.createBooking.mockRejectedValue(new api.ApiError(422, code));

  const bookAndFail = async code => {
    failWith(code);
    const wrapper = await mountApp();
    await click(wrapper, 'Escolher este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    return wrapper;
  };

  it('slot_unavailable goes back to the times with a plain message', async () => {
    const wrapper = await bookAndFail('slot_unavailable');
    expect(wrapper.text()).toContain('Qual horário?');
    expect(wrapper.text()).toContain(
      'Esse horário acabou de ser reservado. Escolha outro.'
    );
    expect(api.getSlots).toHaveBeenCalledWith('conversa', '2026-10-13', 30);
    expect(findAction(wrapper, 'Escolher outro dia')).toBeDefined();
  });

  it.each([
    ['invalid_phone', '#booking-phone', 'Confira o número do WhatsApp'],
    ['invalid_name', '#booking-name', 'Escreva seu nome.'],
    ['invalid_email', '#booking-email', 'Confira o e-mail.'],
    ['email_required', '#booking-email', 'Escreva seu e-mail'],
  ])('%s marks the field', async (code, selector, message) => {
    const wrapper = await bookAndFail(code);
    expect(wrapper.text()).toContain('Seus dados');
    expect(wrapper.find(selector).attributes('aria-invalid')).toBe('true');
    expect(wrapper.text()).toContain(message);
  });

  it.each([
    ['too_many_open', 'Você já tem conversas marcadas'],
    ['booking_failed', 'Não deu para marcar agora'],
    ['network', 'Não deu para marcar agora'],
  ])('%s shows a plain message and a WhatsApp way out', async (code, text) => {
    const wrapper = await bookAndFail(code);
    expect(wrapper.find('[role="alert"]').text()).toContain(text);
    expect(findAction(wrapper, 'Falar no WhatsApp').attributes('href')).toBe(
      'https://wa.me/5511999990000'
    );
  });
});

describe('client link /b/:code', () => {
  it('confirms without typing name or phone', async () => {
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });

    expect(api.getInvite).toHaveBeenCalledWith('Xk4p9Q');
    expect(api.getPage).toHaveBeenCalledWith('conversa', undefined);
    expect(wrapper.text()).toContain('Oi, Marcos! Qual dia fica bom?');

    await click(wrapper, 'Escolher este');
    expect(wrapper.find('[data-testid="confirm-summary"]').text()).toBe(
      'Camila vai te chamar por vídeo no WhatsApp (11) •••••-5678'
    );
    expect(wrapper.find('#booking-name').exists()).toBe(false);
    expect(wrapper.find('#booking-phone').exists()).toBe(false);
    expect(wrapper.find('#booking-email').exists()).toBe(false);

    await submit(wrapper);
    const payload = api.createBooking.mock.calls[0][1];
    expect(payload.invite_code).toBe('Xk4p9Q');
    expect(payload.name).toBe('Marcos');
    expect(payload.phone).toBeUndefined();
    expect(wrapper.text()).toContain('Tudo certo, Marcos!');
  });

  it('calls viewed exactly once, after the first render', async () => {
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    expect(api.markInviteViewed).toHaveBeenCalledTimes(1);
    expect(api.markInviteViewed).toHaveBeenCalledWith('Xk4p9Q');

    await click(wrapper, 'Escolher este');
    await click(wrapper, 'Voltar');
    await click(wrapper, 'Escolher outro dia');
    expect(api.markInviteViewed).toHaveBeenCalledTimes(1);
  });

  it('"Mudar o número" reveals the field and sends the new number', async () => {
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    await click(wrapper, 'Escolher este');
    await click(wrapper, 'Mudar o número');

    expect(findAction(wrapper, 'Mudar o número')).toBeUndefined();
    await wrapper.find('#booking-phone').setValue('11912340000');
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].phone).toBe('+5511912340000');
  });

  it.each([
    ['invalid_name', '#booking-name'],
    ['invalid_phone', '#booking-phone'],
    ['email_required', '#booking-email'],
  ])(
    'reveals the hidden field when the server answers %s',
    async (code, selector) => {
      api.createBooking.mockRejectedValue(new api.ApiError(422, code));
      const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
      await click(wrapper, 'Escolher este');
      expect(wrapper.find(selector).exists()).toBe(false);
      await submit(wrapper);
      expect(wrapper.find(selector).attributes('aria-invalid')).toBe('true');
    }
  );

  it('asks for the number when the contact has no WhatsApp (J1-A11)', async () => {
    api.getInvite.mockResolvedValue({ ...INVITE, phone_masked: null });
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    await click(wrapper, 'Escolher este');
    expect(wrapper.find('#booking-phone').exists()).toBe(true);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
  });

  it('shows "Você já agendou" for a used link', async () => {
    api.getInvite.mockResolvedValue({ ...INVITE, state: 'scheduled' });
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    expect(wrapper.text()).toContain('Você já agendou');
    expect(findAction(wrapper, 'Falar no WhatsApp').attributes('href')).toBe(
      'https://wa.me/5511999990000'
    );
    expect(api.getNextSlot).not.toHaveBeenCalled();
    expect(api.markInviteViewed).toHaveBeenCalledTimes(1);
  });

  it('shows the not-found screen for an unknown code', async () => {
    api.getInvite.mockRejectedValue(new api.ApiError(404, 'not_found'));
    const wrapper = await mountApp({ path: '/b/nope' });
    expect(wrapper.text()).toContain('Este link não vale mais');
    expect(api.getPage).not.toHaveBeenCalled();
  });
});

describe('page states', () => {
  it('paused page offers WhatsApp', async () => {
    const wrapper = await mountApp({
      page: {
        slug: 'conversa',
        paused: true,
        title: 'Conversa',
        brand: { color: '#0B7A5A' },
        contact_whatsapp_url: 'https://wa.me/5511999990000',
      },
    });
    expect(wrapper.text()).toContain('A agenda está fechada agora');
    expect(findAction(wrapper, 'Falar no WhatsApp')).toBeDefined();
    expect(api.getNextSlot).not.toHaveBeenCalled();
  });

  it('404 shows a plain not-found screen', async () => {
    setPath('/book/nope');
    api.getPage.mockRejectedValue(new api.ApiError(404, 'not_found'));
    const wrapper = mount(App);
    await flushPromises();
    expect(wrapper.text()).toContain('Este link não vale mais');
  });

  it('other failures offer "Tentar de novo"', async () => {
    setPath('/book/conversa');
    api.getPage.mockRejectedValueOnce(new api.ApiError(0, 'network'));
    const wrapper = mount(App);
    await flushPromises();
    expect(wrapper.text()).toContain('Não deu para abrir a página');

    api.getPage.mockResolvedValue(PAGE);
    await click(wrapper, 'Tentar de novo');
    expect(wrapper.text()).toContain('Qual dia fica bom?');
  });

  it('an invalid page time zone fails explicitly', async () => {
    const wrapper = await mountApp({
      page: { ...PAGE, timezone: 'Mars/Olympus' },
    });
    expect(wrapper.text()).toContain('Não deu para abrir a página');
  });

  it('passes the preview token and shows the preview banner', async () => {
    const wrapper = await mountApp({
      page: { ...PAGE, preview: true },
      path: '/book/conversa?preview=tk',
    });
    expect(api.getPage).toHaveBeenCalledWith('conversa', 'tk');
    expect(wrapper.text()).toContain('Prévia');
  });

  it('applies a valid brand color and ignores an invalid one', async () => {
    await mountApp();
    expect(document.documentElement.style.getPropertyValue('--brand')).toBe(
      '#0b7a5a'
    );

    await mountApp({
      page: { ...PAGE, brand: { color: 'red;background:url(x)' } },
    });
    expect(document.documentElement.style.getPropertyValue('--brand')).toBe(
      DEFAULT_BRAND_COLOR
    );
  });
});

describe('captcha and consent', () => {
  it('renders hCaptcha only when the page sends a site key', async () => {
    const without = await mountApp();
    await click(without, 'Escolher este');
    expect(without.find('[data-testid="captcha"]').exists()).toBe(false);

    const wrapper = await mountApp({
      page: { ...PAGE, captcha_site_key: 'site-key' },
    });
    await click(wrapper, 'Escolher este');
    expect(wrapper.find('[data-testid="captcha"]').exists()).toBe(true);

    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Confirme que você não é um robô.');

    wrapper.findComponent(CaptchaStub).vm.$emit('verify', 'captcha-ok');
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].captcha_token).toBe('captcha-ok');
  });

  it('shows the WhatsApp notice only when notices_enabled', async () => {
    const off = await mountApp();
    await click(off, 'Escolher este');
    expect(off.find('[data-testid="notices-consent"]').exists()).toBe(false);

    const on = await mountApp({ page: { ...PAGE, notices_enabled: true } });
    await click(on, 'Escolher este');
    expect(on.find('[data-testid="notices-consent"]').text()).toContain(
      'aceita receber os avisos'
    );
    await fillPublicDetails(on);
    await submit(on);
    expect(api.createBooking.mock.calls[0][1].consent.accepted).toBe(true);
  });

  it('keeps the honeypot out of reach and sends it', async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Escolher este');
    const trap = wrapper.find('input[name="company"]');
    expect(trap.attributes('tabindex')).toBe('-1');
    expect(trap.element.closest('[aria-hidden="true"]')).not.toBeNull();
    await trap.setValue('bot inc');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].company).toBe('bot inc');
  });
});

describe('links are always safe', () => {
  it('never turns javascript: into a button and only http(s) joins', async () => {
    api.createBooking.mockResolvedValue({
      ...BOOKED,
      ics_url: `${SCRIPT}alert(1)`,
      contact_whatsapp_url: `${SCRIPT}alert(2)`,
      location: { type: 'custom_link', join_url: `${SCRIPT}alert(3)` },
    });
    const wrapper = await mountApp({
      page: { ...PAGE, contact_whatsapp_url: `${SCRIPT}alert(4)` },
    });
    await click(wrapper, 'Escolher este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);

    expect(wrapper.text()).toContain('Tudo certo');
    wrapper.findAll('a').forEach(link => {
      expect(link.attributes('href')).not.toContain('script:');
    });
    expect(findAction(wrapper, 'Salvar na minha agenda')).toBeUndefined();
    expect(findAction(wrapper, 'Entrar na reunião')).toBeUndefined();
    expect(findAction(wrapper, 'Falar no WhatsApp')).toBeUndefined();
  });

  it('shows "Entrar na reunião" for an https link', async () => {
    api.createBooking.mockResolvedValue({
      ...BOOKED,
      location: { type: 'custom_link', join_url: 'https://meet.example.com/x' },
    });
    const wrapper = await mountApp();
    await click(wrapper, 'Escolher este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    const join = findAction(wrapper, 'Entrar na reunião');
    expect(join.attributes('href')).toBe('https://meet.example.com/x');
    expect(join.attributes('rel')).toBe('noopener noreferrer');
  });
});

describe('no time works', () => {
  it('turns into a contact request', async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Nenhum horário serve?');
    expect(wrapper.text()).toContain('Camila chama você para combinar');

    await wrapper.find('#contact-name').setValue('Ana Souza');
    await wrapper.find('#contact-phone').setValue('11988880000');
    await submit(wrapper);

    expect(api.requestContact).toHaveBeenCalledWith('conversa', {
      name: 'Ana Souza',
      phone: '+5511988880000',
      consent: {
        accepted: false,
        text_key: 'booking_v2.consent.whatsapp_notices',
      },
      company: '',
      form_token: 'form-token',
      captcha_token: undefined,
    });
    expect(wrapper.text()).toContain('Pedido enviado!');
  });

  it('an empty day offers another day and the contact request', async () => {
    api.getSlots.mockResolvedValue({ date: '2026-10-13', slots: [] });
    const wrapper = await mountApp();
    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Não tem horário livre neste dia.');
    expect(findAction(wrapper, 'Escolher outro dia')).toBeDefined();
    expect(findAction(wrapper, 'Nenhum horário serve?')).toBeDefined();
  });

  it('a failed slot load offers a retry', async () => {
    api.getSlots.mockRejectedValueOnce(new api.ApiError(500));
    const wrapper = await mountApp();
    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Não deu para buscar os horários.');
    await click(wrapper, 'Tentar de novo');
    expect(wrapper.text()).toContain('18:00');
  });
});
