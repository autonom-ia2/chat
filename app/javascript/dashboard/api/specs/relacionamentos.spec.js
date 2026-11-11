import relacionamentos from '../relacionamentos';
import ApiClient from '../ApiClient';

// As sete leituras da Lista nova de Relacionamentos (#2894).
describe('#RelacionamentosAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = { get: vi.fn(() => Promise.resolve()) };
  const BASE = '/api/v1/accounts/85/relacionamentos';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/relationships');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('é um ApiClient da conta', () => {
    expect(relacionamentos).toBeInstanceOf(ApiClient);
    expect(relacionamentos.url).toBe(BASE);
  });

  it.each([
    ['pessoas', 'pessoas'],
    ['contagensDePessoas', 'pessoas/contagens'],
    ['todasAsPessoas', 'pessoas/todas'],
    ['empresas', 'empresas'],
    ['contagensDeEmpresas', 'empresas/contagens'],
  ])('%s lê %s com os params do pedido', (metodo, caminho) => {
    const params = { grupo: 'clientes', busca: 'ana' };
    relacionamentos[metodo](params);
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/${caminho}`, {
      params,
    });
  });

  it.each([
    ['resumo', 'resumo'],
    ['opcoesDeFiltro', 'opcoes_de_filtro'],
  ])('%s lê %s sem params', (metodo, caminho) => {
    relacionamentos[metodo]();
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/${caminho}`);
  });
});
