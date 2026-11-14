import trazer from '../relacionamentosTrazer';
import ApiClient from '../ApiClient';

// As rotas de "Trazer minha lista" (#2896): ler a planilha, responder às
// perguntas, consertar as linhas, trocar o destino de uma coluna, trazer, o
// histórico, o andamento e o confirmar que a importação já tinha.
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

  // Fatia 2: responder às perguntas, consertar a linha, deixar de fora, voltar
  // atrás e trazer.
  it('responder escreve as respostas das perguntas, com o corpo como veio', () => {
    trazer.responder(812, { clientes: 'algumas', coluna_cliente: 6 });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      `${BASE}/leituras/812/respostas`,
      { clientes: 'algumas', coluna_cliente: 6 }
    );
  });

  it('consertar escreve na linha da planilha, com o corpo como veio', () => {
    trazer.consertar(812, 14, { valor: '+5511973800014' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      `${BASE}/leituras/812/linhas/14`,
      { valor: '+5511973800014' }
    );
  });

  it('deixarDeFora e reabrir são ações da linha, sem corpo', () => {
    trazer.deixarDeFora(812, 14);
    trazer.reabrir(812, 14);
    expect(axiosMock.post.mock.calls).toEqual([
      [`${BASE}/leituras/812/linhas/14/deixar_de_fora`],
      [`${BASE}/leituras/812/linhas/14/reabrir`],
    ]);
  });

  it('trazer fecha a conferência da leitura', () => {
    trazer.trazer(812);
    expect(axiosMock.post).toHaveBeenCalledWith(`${BASE}/leituras/812/trazer`);
  });

  it('confirmar usa o confirmar da importação de contatos, que já existe', () => {
    trazer.confirmar(812);
    expect(axiosMock.post).toHaveBeenCalledWith(
      `${CONTA}/contact_imports/812/confirm`
    );
  });
});
