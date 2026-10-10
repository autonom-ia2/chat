import crmBookingPages from '../crmBookingPages';
import ApiClient from '../ApiClient';

// Contrato do BookingPagesController (#1187, F1-A) visto pela tela (F1-D).
describe('#CrmBookingPagesAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    put: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };
  const BASE = '/api/v1/accounts/85/crm/booking_pages';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/crm/booking');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('é um ApiClient da conta', () => {
    expect(crmBookingPages).toBeInstanceOf(ApiClient);
    expect(crmBookingPages.url).toBe(BASE);
  });

  it('lista, abre e exclui pelos métodos herdados', () => {
    crmBookingPages.get();
    crmBookingPages.show(4);
    crmBookingPages.delete(4);
    expect(axiosMock.get).toHaveBeenNthCalledWith(1, BASE);
    expect(axiosMock.get).toHaveBeenNthCalledWith(2, `${BASE}/4`);
    expect(axiosMock.delete).toHaveBeenCalledWith(`${BASE}/4`);
  });

  it('cria a partir de um modelo, com nome só quando vem', () => {
    crmBookingPages.create({ templateKey: 'sales_30' });
    crmBookingPages.create({ templateKey: 'blank', title: 'Conversa' });
    expect(axiosMock.post).toHaveBeenNthCalledWith(1, BASE, {
      template_key: 'sales_30',
    });
    expect(axiosMock.post).toHaveBeenNthCalledWith(2, BASE, {
      template_key: 'blank',
      title: 'Conversa',
    });
  });

  it('salva dentro de booking_page', () => {
    crmBookingPages.update(4, { title: 'Nova' });
    expect(axiosMock.patch).toHaveBeenCalledWith(`${BASE}/4`, {
      booking_page: { title: 'Nova' },
    });
  });

  it('publica e pausa nas rotas de membro', () => {
    crmBookingPages.publish(4);
    crmBookingPages.pause(4);
    expect(axiosMock.post).toHaveBeenNthCalledWith(1, `${BASE}/4/publish`);
    expect(axiosMock.post).toHaveBeenNthCalledWith(2, `${BASE}/4/pause`);
  });

  it('envia logo e foto como arquivo no campo file', () => {
    const file = new File(['x'], 'logo.png', { type: 'image/png' });
    crmBookingPages.uploadImage(4, 'logo', file);
    crmBookingPages.uploadImage(4, 'photo', file);
    const [logoUrl, logoBody] = axiosMock.post.mock.calls[0];
    expect(logoUrl).toBe(`${BASE}/4/logo`);
    expect(logoBody.get('file')).toBe(file);
    expect(axiosMock.post.mock.calls[1][0]).toBe(`${BASE}/4/photo`);
  });

  it('lê e troca quem atende', () => {
    crmBookingPages.people(4);
    crmBookingPages.updatePeople(4, [1, 2]);
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/4/people`);
    expect(axiosMock.put).toHaveBeenCalledWith(`${BASE}/4/people`, {
      user_ids: [1, 2],
    });
  });
});
