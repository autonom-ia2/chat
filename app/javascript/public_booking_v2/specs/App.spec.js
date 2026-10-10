import {
  config,
  enableAutoUnmount,
  flushPromises,
  mount,
} from '@vue/test-utils';
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

enableAutoUnmount(afterEach);

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
  weekdays: [1, 2, 3, 4, 5],
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

// `request_id`: 16 a 64 caracteres de UUID ou hex (o que o navegador sorteia).
const isRequestId = value =>
  typeof value === 'string' &&
  value.length >= 16 &&
  value.length <= 64 &&
  [...value].every(char => '0123456789abcdef-'.includes(char));

const setPath = path => window.history.replaceState({}, '', path);

// Fuso de quem abre a página, sem depender do fuso da máquina que roda o teste: todo formato da página passa o fuso
// explícito, e o "fuso do navegador" vem do `resolvedOptions`.
const realResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;
let clientZoneSpy;
const useClientZone = timeZone => {
  clientZoneSpy = vi
    .spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
    .mockImplementation(function resolvedOptions() {
      return { ...realResolvedOptions.call(this), timeZone };
    });
};

const mountApp = async ({
  page = PAGE,
  path = '/book/conversa',
  attach = false,
} = {}) => {
  setPath(path);
  api.getPage.mockResolvedValue(page);
  const wrapper = mount(App, {
    attachTo: attach ? document.body : undefined,
    global: { stubs: { CaptchaField: CaptchaStub } },
  });
  await flushPromises();
  return wrapper;
};

const findAction = (wrapper, text) =>
  wrapper.findAll('button, a').find(node => node.text().includes(text));

// O jsdom entrega o `popstate` do `history.back()` alguns ciclos de tarefa depois.
const HISTORY_TICKS = 4;
const settle = async () => {
  for (let tick = 0; tick < HISTORY_TICKS; tick += 1) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
  }
  await flushPromises();
};

const click = async (wrapper, text) => {
  const node = findAction(wrapper, text);
  if (!node) throw new Error(`No button "${text}" in:\n${wrapper.text()}`);
  await node.trigger('click');
  await settle();
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
  useClientZone('America/Sao_Paulo');
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
  clientZoneSpy?.mockRestore();
});

describe('public link /book/:slug', () => {
  it('books from the earliest shortcut: open → earliest → details → done', async () => {
    const wrapper = await mountApp();

    expect(api.getPage).toHaveBeenCalledWith('conversa', null);
    expect(api.getNextSlot).toHaveBeenCalledWith('conversa', 30);
    expect(wrapper.text()).toContain('Qual dia fica bom?');
    expect(wrapper.text()).toContain('Mais cedo:');

    await click(wrapper, 'Quero este');
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
      request_id: expect.any(String),
    });

    expect(isRequestId(payload.request_id)).toBe(true);
    expect(wrapper.text()).toContain('Tudo certo, Ana!');
    const save = findAction(wrapper, 'Salvar na minha agenda');
    expect(save.attributes('href')).toBe(
      `${window.location.origin}/public/api/v2/ics/tok`
    );
    expect(save.attributes('download')).toBeDefined();
    expect(findAction(wrapper, 'Falar no WhatsApp').attributes('href')).toBe(
      'https://wa.me/5511999990000'
    );
    expect(findAction(wrapper, 'Entrar pelo link')).toBeUndefined();
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
    expect(times).toEqual(['15:00', '16:00']);

    await click(wrapper, '16:00');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].starts_at).toBe(OTHER_SLOT);
  });

  it('hides the time zone line when the client clock is the same as the page', async () => {
    const wrapper = await mountApp();
    expect(wrapper.find('[data-testid="zone-note"]').exists()).toBe(false);
  });

  it('a client in Tokyo sees Tokyo times, with the day when it changes', async () => {
    useClientZone('Asia/Tokyo');
    const wrapper = await mountApp();
    const note = wrapper.find('[data-testid="zone-note"]').text();
    expect(note.startsWith('Horários mostrados em: ')).toBe(true);
    expect(note).toContain('Japão');

    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await flushPromises();
    const labels = wrapper.findAll('ul button').map(node => node.text());
    // 15:00 de Brasília do dia 13 = 03:00 de Tóquio do dia 14: o botão diz o dia.
    expect(labels[0]).toContain('03:00');
    expect(labels[0]).toContain('14');
    expect(labels[0]).not.toBe('03:00');
    expect(wrapper.find('[data-testid="zone-note"]').exists()).toBe(true);
  });

  it('asks for the email when the location requires it (Google Meet)', async () => {
    const wrapper = await mountApp({
      page: {
        ...PAGE,
        locations: [{ type: 'google_meet', requires_email: true }],
      },
    });
    await click(wrapper, 'Quero este');
    expect(wrapper.find('label[for="booking-email"]').text()).toBe(
      'Seu e-mail'
    );

    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Escreva seu e-mail para receber o link.');

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

    await click(wrapper, 'Quero este');
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
    await click(wrapper, 'Quero este');
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
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    return wrapper;
  };

  const requestIds = () =>
    api.createBooking.mock.calls.map(([, payload]) => payload.request_id);

  it('retries a lost answer with the same request_id and starts a new one after a definitive answer', async () => {
    api.createBooking
      .mockRejectedValueOnce(new api.ApiError(0, 'network'))
      .mockRejectedValueOnce(new api.ApiError(500, 'unavailable'))
      .mockRejectedValueOnce(new api.ApiError(422, 'booking_failed'))
      .mockResolvedValueOnce(BOOKED);
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);

    await submit(wrapper);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Não deu para marcar agora'
    );
    await submit(wrapper);
    await submit(wrapper);
    await submit(wrapper);

    const [first, second, third, fourth] = requestIds();
    expect(isRequestId(first)).toBe(true);
    expect(second).toBe(first);
    expect(third).toBe(first);
    expect(isRequestId(fourth)).toBe(true);
    expect(fourth).not.toBe(first);
    expect(wrapper.text()).toContain('Tudo certo, Ana!');
  });

  it('uses a new request_id after choosing another time', async () => {
    failWith('slot_unavailable');
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);

    api.createBooking.mockResolvedValue(BOOKED);
    await click(wrapper, '16:00');
    await fillPublicDetails(wrapper);
    await submit(wrapper);

    const [first, second] = requestIds();
    expect(api.createBooking.mock.calls[1][1].starts_at).toBe(OTHER_SLOT);
    expect(isRequestId(second)).toBe(true);
    expect(second).not.toBe(first);
  });

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
    ['too_many_open', 'Você já tem horários marcados'],
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

    await click(wrapper, 'Quero este');
    expect(wrapper.find('[data-testid="confirm-summary"]').text()).toBe(
      'Camila vai chamar você por vídeo no WhatsApp (11) •••••-5678'
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

    await click(wrapper, 'Quero este');
    await click(wrapper, 'Voltar');
    expect(wrapper.text()).toContain('Oi, Marcos! Qual dia fica bom?');
    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await settle();
    expect(api.markInviteViewed).toHaveBeenCalledTimes(1);
  });

  it('"Mudar o número" reveals the field and sends the new number', async () => {
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    await click(wrapper, 'Quero este');
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
      await click(wrapper, 'Quero este');
      expect(wrapper.find(selector).exists()).toBe(false);
      await submit(wrapper);
      expect(wrapper.find(selector).attributes('aria-invalid')).toBe('true');
    }
  );

  it('asks for the number when the contact has no WhatsApp (J1-A11)', async () => {
    api.getInvite.mockResolvedValue({ ...INVITE, phone_masked: null });
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    await click(wrapper, 'Quero este');
    expect(wrapper.find('#booking-phone').exists()).toBe(true);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
  });

  it('shows "Você já agendou" with the booked day and time', async () => {
    api.getInvite.mockResolvedValue({
      ...INVITE,
      state: 'scheduled',
      starts_at: NEXT_SLOT,
      timezone: 'America/Sao_Paulo',
    });
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    expect(wrapper.text()).toContain('Você já agendou');
    expect(wrapper.find('[data-testid="already-when"]').text()).toContain(
      'terça-feira, 13 de outubro'
    );
    expect(wrapper.find('[data-testid="already-when"]').text()).toContain(
      '15:00'
    );
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

    await click(wrapper, 'Quero este');
    expect(wrapper.find('[data-testid="preview-no-booking"]').text()).toBe(
      'Isto é uma prévia. Ninguém consegue marcar por aqui.'
    );
    expect(findAction(wrapper, 'Confirmar')).toBeUndefined();
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(api.createBooking).not.toHaveBeenCalled();
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
    await click(without, 'Quero este');
    expect(without.find('[data-testid="captcha"]').exists()).toBe(false);

    const wrapper = await mountApp({
      page: { ...PAGE, captcha_site_key: 'site-key' },
    });
    await click(wrapper, 'Quero este');
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
    await click(off, 'Quero este');
    expect(off.find('[data-testid="notices-consent"]').exists()).toBe(false);

    const on = await mountApp({ page: { ...PAGE, notices_enabled: true } });
    await click(on, 'Quero este');
    expect(on.find('[data-testid="notices-consent"]').text()).toContain(
      'aceita receber avisos sobre este horário'
    );
    await fillPublicDetails(on);
    await submit(on);
    expect(api.createBooking.mock.calls[0][1].consent.accepted).toBe(true);
  });

  it('keeps the honeypot out of reach and sends it', async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    expect(wrapper.find('input[name="company"]').exists()).toBe(false);
    const trap = wrapper.find('input[name="hp_field_x"]');
    expect(trap.attributes('autocomplete')).toBe('off');
    expect(wrapper.find('label[for="booking-hp-field"]').text()).not.toContain(
      'Company'
    );
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
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);

    expect(wrapper.text()).toContain('Tudo certo');
    wrapper.findAll('a').forEach(link => {
      expect(link.attributes('href')).not.toContain('script:');
    });
    expect(findAction(wrapper, 'Salvar na minha agenda')).toBeUndefined();
    expect(findAction(wrapper, 'Entrar pelo link')).toBeUndefined();
    expect(findAction(wrapper, 'Falar no WhatsApp')).toBeUndefined();
  });

  it('shows "Entrar na reunião" for an https link', async () => {
    api.createBooking.mockResolvedValue({
      ...BOOKED,
      location: { type: 'custom_link', join_url: 'https://meet.example.com/x' },
    });
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    const join = findAction(wrapper, 'Entrar pelo link');
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
    expect(wrapper.text()).toContain('15:00');
  });
});

describe('days, durations and places', () => {
  it('never offers a closed weekday and follows the page window up to 90 days', async () => {
    const wrapper = await mountApp({
      page: { ...PAGE, booking_window_days: 120 },
    });
    const labels = wrapper
      .findAll('button[aria-label]')
      .map(node => node.attributes('aria-label'));
    // De segunda 12/10 a 90 dias depois: 13 semanas, só os dias úteis.
    expect(labels).toHaveLength(65);
    expect(labels.some(label => label.startsWith('sábado'))).toBe(false);
    expect(labels.some(label => label.startsWith('domingo'))).toBe(false);
  });

  it('shows the chosen duration in the header and drops the old earliest time', async () => {
    const wrapper = await mountApp({ page: { ...PAGE, durations: [30, 60] } });
    expect(wrapper.find('header').text()).toContain('30 minutos');
    expect(wrapper.text()).toContain('Mais cedo:');

    api.getNextSlot.mockReturnValue(new Promise(() => {}));
    await wrapper.find('input[name="booking-duration"][value="60"]').setValue();
    await flushPromises();
    expect(wrapper.find('header').text()).toContain('60 minutos');
    expect(wrapper.text()).not.toContain('Mais cedo:');
  });

  it('uses the server label and shows the address before confirming', async () => {
    const wrapper = await mountApp({
      page: {
        ...PAGE,
        locations: [
          {
            type: 'in_person',
            label: 'Escritório Paulista',
            address: 'Av. Paulista, 1000',
            requires_email: false,
          },
        ],
      },
    });
    await click(wrapper, 'Quero este');
    const place = wrapper.find('[data-testid="only-location"]').text();
    expect(place).toContain('Escritório Paulista');
    expect(place).toContain('Endereço: Av. Paulista, 1000');
  });

  it('uses the server labels in the location cards', async () => {
    const wrapper = await mountApp({
      page: {
        ...PAGE,
        locations: [
          { type: 'whatsapp_video', label: 'Vídeo', requires_email: false },
          {
            type: 'in_person',
            label: 'Loja do centro',
            address: 'Rua A, 1',
            requires_email: false,
          },
        ],
      },
    });
    await click(wrapper, 'Quero este');
    const cards = wrapper
      .find('input[name="booking-location"]')
      .element.closest('fieldset').textContent;
    expect(cards).toContain('Loja do centro');
    expect(cards).toContain('Endereço: Rua A, 1');
  });
});

describe('phone back button', () => {
  it('goes back one screen instead of leaving the page', async () => {
    const wrapper = await mountApp();
    await wrapper.find('button[aria-label*="13"]').trigger('click');
    await settle();
    expect(wrapper.text()).toContain('Qual horário?');
    await click(wrapper, '16:00');
    expect(wrapper.text()).toContain('Seus dados');

    window.history.back();
    await settle();
    expect(wrapper.text()).toContain('Qual horário?');
    window.history.back();
    await settle();
    expect(wrapper.text()).toContain('Qual dia fica bom?');
  });

  it('does not stack entries when the page loads again', async () => {
    const before = window.history.length;
    const wrapper = await mountApp();
    expect(window.history.length).toBe(before);

    api.getPage.mockRejectedValueOnce(new api.ApiError(0, 'network'));
    await wrapper.vm.$.setupState.load();
    await settle();
    expect(window.history.length).toBe(before);
  });

  it('keeps the confirmation on screen after booking', async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(wrapper.text()).toContain('Tudo certo, Ana!');

    window.history.back();
    await settle();
    expect(wrapper.text()).toContain('Tudo certo, Ana!');
  });
});

describe('form token older than the server accepts', () => {
  const LOADED_AT = new Date('2026-10-12T12:00:00Z');
  const minutesLater = minutes =>
    new Date(LOADED_AT.getTime() + minutes * 60 * 1000);

  beforeEach(() => {
    vi.useRealTimers();
    vi.useFakeTimers({ toFake: ['Date', 'setTimeout'], now: LOADED_AT });
  });

  const openDetails = async () => {
    const wrapper = await mountApp();
    await findAction(wrapper, 'Quero este').trigger('click');
    await flushPromises();
    await fillPublicDetails(wrapper);
    return wrapper;
  };

  it('fetches a fresh token before sending after 1h45', async () => {
    const wrapper = await openDetails();
    api.getPage.mockResolvedValue({ ...PAGE, form_token: 'form-token-2' });
    vi.setSystemTime(minutesLater(110));

    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(api.getPage).toHaveBeenCalledTimes(2);
    expect(api.createBooking).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(2100);
    await flushPromises();
    expect(api.createBooking).toHaveBeenCalledTimes(1);
    expect(api.createBooking.mock.calls[0][1].form_token).toBe('form-token-2');
    expect(wrapper.text()).toContain('Tudo certo, Ana!');
  });

  it('renews an old token once after booking_failed, with the same request_id', async () => {
    const wrapper = await openDetails();
    api.createBooking
      .mockRejectedValueOnce(new api.ApiError(422, 'booking_failed'))
      .mockResolvedValueOnce(BOOKED);
    api.getPage.mockResolvedValue({ ...PAGE, form_token: 'form-token-2' });
    vi.setSystemTime(minutesLater(70));

    await wrapper.find('form').trigger('submit');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(2100);
    await flushPromises();

    const [first, second] = api.createBooking.mock.calls.map(
      ([, payload]) => payload
    );
    expect(first.form_token).toBe('form-token');
    expect(second.form_token).toBe('form-token-2');
    expect(second.request_id).toBe(first.request_id);
    expect(wrapper.text()).toContain('Tudo certo, Ana!');
  });

  it('does not loop: a fresh token that fails shows the message', async () => {
    const wrapper = await openDetails();
    api.createBooking.mockRejectedValue(
      new api.ApiError(422, 'booking_failed')
    );

    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(api.getPage).toHaveBeenCalledTimes(1);
    expect(api.createBooking).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Não deu para marcar agora'
    );
  });
});

describe('phone number typing', () => {
  it.each([
    ['+55 11 98765-4321', '(11) 98765-4321', '+5511987654321'],
    ['5511987654321', '(11) 98765-4321', '+5511987654321'],
    ['011 98765-4321', '(11) 98765-4321', '+5511987654321'],
    ['119888800001', '(11) 98888-0000', '+5511988880000'],
  ])('"%s" shows %s and sends exactly that', async (typed, shown, sent) => {
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await wrapper.find('#booking-name').setValue('Ana Souza');
    await wrapper.find('#booking-phone').setValue(typed);
    expect(wrapper.find('#booking-phone').element.value).toBe(shown);
    await submit(wrapper);
    expect(api.createBooking.mock.calls[0][1].phone).toBe(sent);
  });
});

describe('focus and announcements', () => {
  it('moves the focus to the first wrong field, with no pile of alerts', async () => {
    const wrapper = await mountApp({ attach: true });
    await click(wrapper, 'Quero este');
    await submit(wrapper);
    expect(document.activeElement?.id).toBe('booking-name');
    expect(wrapper.findAll('[role="alert"]')).toHaveLength(0);
    expect(
      wrapper.find('#booking-name').attributes('aria-describedby')
    ).toContain('booking-name-error');
  });

  it('a field error from the server also takes the focus', async () => {
    api.createBooking.mockRejectedValue(new api.ApiError(422, 'invalid_phone'));
    const wrapper = await mountApp({ attach: true });
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    expect(document.activeElement?.id).toBe('booking-phone');
  });

  it('announces the sent contact request by focusing its title', async () => {
    const wrapper = await mountApp({ attach: true });
    await click(wrapper, 'Nenhum horário serve?');
    await wrapper.find('#contact-name').setValue('Ana Souza');
    await wrapper.find('#contact-phone').setValue('11988880000');
    await submit(wrapper);
    expect(document.activeElement?.textContent.trim()).toBe('Pedido enviado!');
  });
});

describe('no time works from the client link', () => {
  it('does not ask name and WhatsApp again and sends the invite code', async () => {
    const wrapper = await mountApp({ path: '/b/Xk4p9Q' });
    await click(wrapper, 'Nenhum horário serve?');
    expect(wrapper.text()).toContain('Camila chama você no WhatsApp');
    expect(wrapper.find('#contact-name').exists()).toBe(false);
    expect(wrapper.find('#contact-phone').exists()).toBe(false);

    await submit(wrapper);
    expect(api.requestContact).toHaveBeenCalledWith(
      'conversa',
      expect.objectContaining({
        name: undefined,
        phone: undefined,
        invite_code: 'Xk4p9Q',
      })
    );
    expect(wrapper.text()).toContain('Pedido enviado!');
  });
});

describe('after booking', () => {
  const book = async () => {
    const wrapper = await mountApp();
    await click(wrapper, 'Quero este');
    await fillPublicDetails(wrapper);
    await submit(wrapper);
    return wrapper;
  };

  it('hands over the link to change or cancel, with copy and open', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText },
      configurable: true,
    });
    const wrapper = await book();

    const box = wrapper.find('[data-testid="manage-link"]');
    expect(box.text()).toContain('Guarde este link para mudar ou cancelar');
    expect(box.find('input').element.value).toBe(BOOKED.manage_url);
    expect(findAction(wrapper, 'Abrir link').attributes('href')).toBe(
      BOOKED.manage_url
    );

    await click(wrapper, 'Copiar link');
    expect(writeText).toHaveBeenCalledWith(BOOKED.manage_url);
    expect(box.find('[role="status"]').text()).toBe('Link copiado.');
  });

  it('offers Google Calendar next to the .ics, with only title, time and place', async () => {
    const wrapper = await book();
    const google = findAction(wrapper, 'Pôr na Agenda do Google');
    const url = new URL(google.attributes('href'));
    expect(url.origin + url.pathname).toBe(
      'https://calendar.google.com/calendar/render'
    );
    expect(url.searchParams.get('action')).toBe('TEMPLATE');
    expect(url.searchParams.get('text')).toBe('Horário com Camila');
    expect(url.searchParams.get('dates')).toBe(
      '20261013T180000Z/20261013T183000Z'
    );
    expect(google.attributes('href')).not.toContain('Ana');
    expect(google.attributes('href')).not.toContain('5511988880000');
  });
});
