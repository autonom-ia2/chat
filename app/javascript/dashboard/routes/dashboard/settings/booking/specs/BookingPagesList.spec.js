import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import BookingPagesList from '../components/BookingPagesList.vue';

// Lista de páginas (#1187, F1-D): estados, cartões, ações e quem só vê.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    get: vi.fn(),
    publish: vi.fn(),
    pause: vi.fn(),
    delete: vi.fn(),
  },
}));

const page = (id, extra = {}) => ({
  id,
  title: `Página ${id}`,
  enabled: true,
  public_url: `https://chat.exemplo.com/book/slug-${id}`,
  upcoming_meetings_count: 0,
  attention: false,
  ...extra,
});

const mountList = (canManage = true) =>
  mount(BookingPagesList, { props: { canManage } });

const WRITE_BUTTONS = [
  '[data-create]',
  '[data-edit]',
  '[data-pause]',
  '[data-publish]',
  '[data-delete]',
];

describe('BookingPagesList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('mostra o esqueleto enquanto carrega', () => {
    BookingPagesAPI.get.mockReturnValue(new Promise(() => {}));
    const wrapper = mountList();
    expect(wrapper.find('[data-loading]').attributes('aria-busy')).toBe('true');
  });

  it('erro diz o que houve e tenta de novo', async () => {
    BookingPagesAPI.get.mockRejectedValueOnce(new Error('rede'));
    BookingPagesAPI.get.mockResolvedValueOnce({ data: { payload: [] } });
    const wrapper = mountList();
    await flushPromises();
    expect(wrapper.find('[data-error]').text()).toContain('BOOKING.LIST.ERROR');
    await wrapper.find('[data-error] button').trigger('click');
    await flushPromises();
    expect(BookingPagesAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-empty]').exists()).toBe(true);
  });

  it('vazio: uma frase e um botão que abre a criação', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountList();
    await flushPromises();
    const empty = wrapper.find('[data-empty]');
    expect(empty.findAll('p')).toHaveLength(1);
    expect(empty.text()).toContain('BOOKING.LIST.EMPTY');
    expect(empty.findAll('button')).toHaveLength(1);
    await empty.find('[data-create]').trigger('click');
    expect(wrapper.emitted('create')).toHaveLength(1);
  });

  it('um cartão por página, com situação, contagem e o link', async () => {
    BookingPagesAPI.get.mockResolvedValue({
      data: {
        payload: [
          page(1, { upcoming_meetings_count: 3 }),
          page(2, { enabled: false }),
        ],
      },
    });
    const wrapper = mountList();
    await flushPromises();
    const cards = wrapper.findAll('[data-page]');
    expect(cards).toHaveLength(2);
    expect(cards[0].find('h3').text()).toBe('Página 1');
    expect(cards[0].find('[data-status]').text()).toBe(
      'BOOKING.CARD.PUBLISHED'
    );
    expect(cards[0].text()).toContain('BOOKING.CARD.UPCOMING 3');
    expect(cards[0].find('[data-pause]').exists()).toBe(true);
    expect(cards[1].find('[data-status]').text()).toBe('BOOKING.CARD.PAUSED');
    expect(cards[1].find('[data-publish]').exists()).toBe(true);
    expect(cards[0].find('[data-link-url]').text()).toBe(
      'https://chat.exemplo.com/book/slug-1'
    );
    expect(cards[0].find('[data-open]').attributes('href')).toBe(
      'https://chat.exemplo.com/book/slug-1'
    );
    expect(cards[0].find('[data-open]').attributes('rel')).toContain(
      'noopener'
    );
  });

  it('aviso de atenção quando quem atende não pode receber reuniões', async () => {
    BookingPagesAPI.get.mockResolvedValue({
      data: { payload: [page(1, { attention: true }), page(2)] },
    });
    const wrapper = mountList();
    await flushPromises();
    const cards = wrapper.findAll('[data-page]');
    expect(cards[0].find('[data-attention]').text()).toBe(
      'BOOKING.CARD.ATTENTION'
    );
    expect(cards[1].find('[data-attention]').exists()).toBe(false);
  });

  it('copiar link usa a área de transferência e avisa', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [page(1)] } });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.find('[data-copy]').trigger('click');
    await flushPromises();
    expect(copyTextToClipboard).toHaveBeenCalledWith(
      'https://chat.exemplo.com/book/slug-1'
    );
    expect(useAlert).toHaveBeenCalledWith('BOOKING.LINK.COPIED');
  });

  it('quem só vê enxerga as páginas e o link, sem botão de escrita', async () => {
    BookingPagesAPI.get.mockResolvedValue({
      data: { payload: [page(1), page(2, { enabled: false })] },
    });
    const wrapper = mountList(false);
    await flushPromises();
    expect(wrapper.findAll('[data-page]')).toHaveLength(2);
    WRITE_BUTTONS.forEach(selector => {
      expect(wrapper.find(selector).exists()).toBe(false);
    });
    expect(wrapper.find('[data-copy]').exists()).toBe(true);
    await wrapper.find('[data-view]').trigger('click');
    expect(wrapper.emitted('view')[0][0].id).toBe(1);
  });

  it('quem só vê, sem páginas, não recebe botão de criar', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountList(false);
    await flushPromises();
    expect(wrapper.find('[data-empty]').text()).toContain(
      'BOOKING.LIST.EMPTY_VIEW_ONLY'
    );
    expect(wrapper.find('[data-create]').exists()).toBe(false);
  });

  it('pausar troca a situação do cartão', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [page(1)] } });
    BookingPagesAPI.pause.mockResolvedValue({
      data: { payload: page(1, { enabled: false }) },
    });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.find('[data-pause]').trigger('click');
    await flushPromises();
    expect(BookingPagesAPI.pause).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-status]').text()).toBe('BOOKING.CARD.PAUSED');
    expect(useAlert).toHaveBeenCalledWith('BOOKING.CARD.PAUSED_OK');
  });

  it('publicar com pendência mostra o que falta em linguagem simples', async () => {
    BookingPagesAPI.get.mockResolvedValue({
      data: { payload: [page(1, { enabled: false })] },
    });
    BookingPagesAPI.publish.mockRejectedValue({
      response: { status: 422, data: { missing: ['host', 'location'] } },
    });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.find('[data-publish]').trigger('click');
    await flushPromises();
    const notice = wrapper.find('[data-notice]').text();
    expect(notice).toContain('BOOKING.CARD.MISSING');
    expect(notice).toContain('BOOKING.PREVIEW.MISSING.HOST');
    expect(notice).toContain('BOOKING.PREVIEW.MISSING.LOCATION');
    expect(wrapper.find('[data-status]').text()).toBe('BOOKING.CARD.PAUSED');
  });

  it('excluir pede confirmação antes de chamar a API', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [page(1)] } });
    BookingPagesAPI.delete.mockResolvedValue({});
    const wrapper = mountList();
    await flushPromises();
    await wrapper.find('[data-delete]').trigger('click');
    expect(BookingPagesAPI.delete).not.toHaveBeenCalled();
    expect(wrapper.find('[data-confirm]').exists()).toBe(true);
    await wrapper.find('[data-confirm-no]').trigger('click');
    expect(wrapper.find('[data-confirm]').exists()).toBe(false);
    await wrapper.find('[data-delete]').trigger('click');
    await wrapper.find('[data-confirm-yes]').trigger('click');
    await flushPromises();
    expect(BookingPagesAPI.delete).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-page]').exists()).toBe(false);
  });

  it('excluir página com reunião marcada (409) explica e mantém o cartão', async () => {
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [page(1)] } });
    BookingPagesAPI.delete.mockRejectedValue({
      response: { status: 409, data: { upcoming_meetings_count: 2 } },
    });
    const wrapper = mountList();
    await flushPromises();
    await wrapper.find('[data-delete]').trigger('click');
    await wrapper.find('[data-confirm-yes]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-page]').exists()).toBe(true);
    expect(wrapper.find('[data-notice]').text()).toBe(
      'BOOKING.CARD.DELETE_BLOCKED'
    );
  });
});
