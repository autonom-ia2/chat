import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import App from '../App.vue';
import * as api from '../api';
import BookingPreviewCard from '../../dashboard/routes/dashboard/settings/booking/components/BookingPreviewCard.vue';
import BookingBrandSample from '../../dashboard/routes/dashboard/settings/booking/components/BookingBrandSample.vue';
import { pageToForm } from '../../dashboard/routes/dashboard/settings/booking/bookingPageForm';
import messages from '../i18n';

// A prévia do painel tem de ser a página de verdade (#1289). Este teste abre a página pública (App.vue) e a prévia
// do assistente com os mesmos dados e compara a ÁRVORE de elementos e classes das duas. Se alguém voltar a desenhar
// a prévia à mão (a faixa colorida de antes, por exemplo) ou mudar a página sem a prévia acompanhar, ele falha.
vi.mock('../api', async importOriginal => {
  const actual = await importOriginal();
  return { ...actual, getPage: vi.fn(), getNextSlot: vi.fn() };
});

enableAutoUnmount(afterEach);

const LOGO = 'https://cdn.exemplo.com/logo.png';
const AVATAR = 'https://cdn.exemplo.com/avatar.png';
const SAVED_PHOTO = 'https://cdn.exemplo.com/guardada.png';
const PAGE_PHOTO = 'https://cdn.exemplo.com/pagina.png';

// Os fatos de uma página, e as duas formas em que o servidor a entrega. As duas saem dos mesmos fatos, seguindo o
// contrato dos serializadores (o rspec booking_pages_identity_spec confere que o servidor cumpre esse contrato).
const FACTS = {
  timezone: 'America/Sao_Paulo',
  closedDates: [],
  nextSlot: '2026-10-13T12:00:00.000Z',
  avatar: null,
  savedPhoto: null,
  pagePhoto: null,
};

// O que o painel recebe (PageSerializer#full): a pessoa com a foto do perfil e a foto guardada, e `preview` com o
// fuso e os feriados fechados.
const panelPage = facts => ({
  id: 7,
  title: 'Conversa de 30 min',
  description: 'Uma conversa rápida para entender o que você precisa.',
  duration_minutes: 30,
  slot_durations: [],
  booking_window_days: 7,
  close_holidays: true,
  working_hours: { start_hour: 9, end_hour: 17, weekdays: [1, 2, 3, 4, 5] },
  brand: { color: '#FFE066', headline: 'Vamos conversar', logo_align: 'right' },
  logo_url: LOGO,
  photo_url: facts.pagePhoto,
  people: [
    {
      id: 1,
      name: 'Camila',
      avatar_url: facts.avatar,
      booking_photo_url: facts.savedPhoto,
    },
  ],
  locations: [{ type: 'whatsapp_video' }],
  preview: { timezone: facts.timezone, closed_dates: facts.closedDates },
});

// O que a página pública recebe da mesma página (PublicPageSerializer#full): `agent_photo_url` já é a foto guardada
// ou, sem ela, a do perfil.
const publicPage = facts => {
  const panel = panelPage(facts);
  return {
    slug: 'conversa',
    paused: false,
    preview: false,
    title: panel.title,
    description: panel.description,
    agent_name: 'Camila',
    agent_photo_url: facts.savedPhoto || facts.avatar,
    duration_minutes: 30,
    durations: [30],
    timezone: facts.timezone,
    booking_window_days: 7,
    weekdays: [1, 2, 3, 4, 5],
    closed_dates: facts.closedDates,
    brand: { ...panel.brand, logo_url: LOGO, photo_url: facts.pagePhoto },
    locations: [{ type: 'whatsapp_video', requires_email: false }],
    form_token: 'form-token',
    captcha_site_key: null,
    notices_enabled: false,
  };
};

const PANEL_PAGE = panelPage(FACTS);

// Elemento → { tag, classes em ordem, filhos }. Texto e atributos ficam de fora: o que se compara é a estrutura.
const shape = element => ({
  tag: element.tagName.toLowerCase(),
  classes: [...element.classList].sort(),
  children: [...element.children].map(shape),
});

const realResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;
let zoneSpy;

const mountPublicPage = async (facts = FACTS) => {
  window.history.replaceState({}, '', '/book/conversa');
  api.getPage.mockResolvedValue(publicPage(facts));
  api.getNextSlot.mockResolvedValue({ starts_at: facts.nextSlot });
  const wrapper = mount(App);
  await flushPromises();
  return wrapper;
};

const mountPreview = async (component = BookingPreviewCard, facts = FACTS) => {
  const page = panelPage(facts);
  const wrapper = mount(component, {
    props: { form: pageToForm(page), page },
  });
  await flushPromises();
  return wrapper;
};

beforeEach(() => {
  zoneSpy = vi
    .spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
    .mockImplementation(function resolvedOptions() {
      return {
        ...realResolvedOptions.call(this),
        timeZone: 'America/Sao_Paulo',
      };
    });
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-12T12:00:00Z'));
});

afterEach(() => {
  vi.useRealTimers();
  zoneSpy?.mockRestore();
});

describe('prévia do assistente × página pública', () => {
  it('o cabeçalho da prévia tem a mesma estrutura do cabeçalho da página', async () => {
    const page = await mountPublicPage();
    const preview = await mountPreview();
    const real = page.find('[data-brand-header]');
    const shown = preview.find('[data-brand-header]');

    expect(real.exists()).toBe(true);
    expect(shown.exists()).toBe(true);
    expect(shape(shown.element)).toEqual(shape(real.element));
  });

  it('a tela inteira da prévia (cartão, título, dias, botões) é a da página', async () => {
    const page = await mountPublicPage();
    const preview = await mountPreview();

    expect(shape(preview.find('[data-page-card]').element)).toEqual(
      shape(page.find('[data-page-card]').element)
    );
  });

  // A prévia vai primeiro: é ela que põe os textos da página pública no catálogo do painel.
  const both = async facts => {
    const preview = await mountPreview(BookingPreviewCard, facts);
    const page = await mountPublicPage(facts);
    return {
      preview: preview.find('[data-page-card]'),
      page: page.find('[data-page-card]'),
    };
  };
  const photoOf = card => card.find('[data-brand-header] img.rounded-full');

  it('página em outro fuso e com feriado fechado: mesmos dias, mesmo "Mais cedo", mesmo aviso de fuso', async () => {
    // Quem vê está em São Paulo; a página é de Tóquio (lá já são 21:00 de segunda, 12/10). Terça 13/10 está
    // fechada: a primeira abertura é quarta 14/10 às 09:00 de Tóquio (00:00 UTC).
    const { preview, page } = await both({
      ...FACTS,
      timezone: 'Asia/Tokyo',
      closedDates: ['2026-10-13'],
      nextSlot: '2026-10-14T00:00:00.000Z',
    });

    expect(shape(preview.element)).toEqual(shape(page.element));
    expect(preview.text()).toBe(page.text());
    expect(page.find('[data-testid="zone-note"]').exists()).toBe(true);
    const days = card =>
      card.findAll('ul button').map(button => button.attributes('aria-label'));
    expect(days(preview)).toEqual(days(page));
    expect(days(preview).some(label => label.includes('13'))).toBe(false);
  });

  it('foto: guardada pela pessoa vem antes da do perfil, e a da página antes das duas, igual à página', async () => {
    const saved = await both({
      ...FACTS,
      avatar: AVATAR,
      savedPhoto: SAVED_PHOTO,
    });
    expect(photoOf(saved.page).attributes('src')).toBe(SAVED_PHOTO);
    expect(photoOf(saved.preview).attributes('src')).toBe(SAVED_PHOTO);

    const profile = await both({ ...FACTS, avatar: AVATAR });
    expect(photoOf(profile.page).attributes('src')).toBe(AVATAR);
    expect(photoOf(profile.preview).attributes('src')).toBe(AVATAR);

    const own = await both({
      ...FACTS,
      avatar: AVATAR,
      savedPhoto: SAVED_PHOTO,
      pagePhoto: PAGE_PHOTO,
    });
    expect(photoOf(own.page).attributes('src')).toBe(PAGE_PHOTO);
    expect(photoOf(own.preview).attributes('src')).toBe(PAGE_PHOTO);
    expect(shape(own.preview.element)).toEqual(shape(own.page.element));
  });

  it('a prévia mostra os mesmos textos da página, no idioma do painel', async () => {
    const preview = await mountPreview();
    const text = preview.text();
    expect(text).toContain('Vamos conversar');
    expect(text).toContain('Camila');
    expect(text).toContain(PANEL_PAGE.description);
    expect(text).toContain(messages.en.BOOKING_V2.DATE.TITLE);
    expect(text).not.toContain('BOOKING_V2.');
  });

  it('limpa, sem faixa: nada no cabeçalho tem fundo na cor da marca', async () => {
    const preview = await mountPreview();
    const header = preview.find('[data-brand-header]');
    const painted = [header, ...header.findAll('*')].filter(node =>
      node.classes().some(name => name.startsWith('bg-[var(--brand'))
    );
    // Com logo e sem foto, só o círculo da inicial leva a cor.
    expect(painted.map(node => node.text())).toEqual(['C']);
    expect(header.text()).toContain('Vamos conversar');
  });

  it('a prévia aplica a cor do mesmo jeito que a página: três valores no próprio elemento', async () => {
    const page = await mountPublicPage();
    const preview = await mountPreview();
    const root = preview.find('[data-preview]').element;
    ['--brand', '--brand-fill', '--brand-on'].forEach(name => {
      expect(root.style.getPropertyValue(name)).toBe(
        document.documentElement.style.getPropertyValue(name)
      );
      expect(root.style.getPropertyValue(name)).not.toBe('');
    });
    expect(root.style.getPropertyValue('--brand-fill')).toBe('#ffe066');
    expect(root.style.getPropertyValue('--brand-on')).toBe('#000000');
    expect(page.exists()).toBe(true);
  });

  it('os botões da prévia não recebem clique nem foco (inert)', async () => {
    const preview = await mountPreview();
    const buttons = preview.findAll('button');
    expect(buttons.length).toBeGreaterThan(0);
    buttons.forEach(button => {
      expect(button.element.closest('[inert]')).not.toBeNull();
    });
  });

  it('a amostra do passo Sua marca usa o mesmo cabeçalho e os mesmos botões', async () => {
    const page = await mountPublicPage();
    const sample = await mountPreview(BookingBrandSample);

    expect(shape(sample.find('[data-brand-header]').element)).toEqual(
      shape(page.find('[data-brand-header]').element)
    );
    const [primary, secondary] = sample.findAll('button');
    expect(primary.classes()).toContain('bg-[var(--brand-fill)]');
    expect(primary.classes()).toContain('text-[var(--brand-on)]');
    expect(secondary.classes()).toContain('border-[var(--brand)]');
    expect(sample.find('[data-logo-box]').attributes('data-logo-align')).toBe(
      'right'
    );
  });
});
