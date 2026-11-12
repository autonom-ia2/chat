import trazer from '../relacionamentosTrazer';
import ApiClient from '../ApiClient';

// As rotas de "Trazer minha lista" (#2896): ler a planilha, trocar o destino de
// uma coluna, o histórico, o andamento e o confirmar que a importação já tinha.
describe('#RelacionamentosTrazerAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
  };
  const CONTA = '/api/v1/accounts/85';
  const BASE = `${CONTA}/relacionamentos/trazer`;

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/relacionamentos/trazer');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('é um ApiClient da conta', () => {
    expect(trazer).toBeInstanceOf(ApiClient);
    expect(trazer.url).toBe(BASE);
  });

  it('enviar manda a planilha em multipart, no campo `arquivo`', () => {
    const planilha = new File(['nome;telefone'], 'clientes.csv');
    trazer.enviar(planilha);
    const [url, corpo, config] = axiosMock.post.mock.calls[0];
    expect(url).toBe(`${BASE}/leituras`);
    expect(corpo).toBeInstanceOf(FormData);
    expect([...corpo.keys()]).toEqual(['arquivo']);
    expect(corpo.get('arquivo').name).toBe('clientes.csv');
    expect(config).toEqual({
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  });

  it('leitura lê a leitura pelo id, na página pedida', () => {
    trazer.leitura(812, 3);
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/leituras/812`, {
      params: { pagina: 3 },
    });
  });

  it('leitura sem página pede a primeira', () => {
    trazer.leitura(812);
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/leituras/812`, {
      params: { pagina: 1 },
    });
  });

  it('trocarColuna escreve na coluna pelo índice, com o corpo como veio', () => {
    trazer.trocarColuna(812, 6, { destino: 'nao_guardar' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      `${BASE}/leituras/812/colunas/6`,
      { destino: 'nao_guardar' }
    );
  });

  it('listas lê o histórico, sem params', () => {
    trazer.listas();
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/listas`);
  });

  it('andamento lê o andamento da lista pelo id', () => {
    trazer.andamento(812);
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/listas/812/andamento`);
  });

  it('confirmar usa o confirmar da importação de contatos, que já existe', () => {
    trazer.confirmar(812);
    expect(axiosMock.post).toHaveBeenCalledWith(
      `${CONTA}/contact_imports/812/confirm`
    );
  });
});
