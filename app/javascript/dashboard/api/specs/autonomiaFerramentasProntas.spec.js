import ferramentasProntas from '../autonomia/ferramentasProntas';
import ApiClient from '../ApiClient';

// #2858 F2 — o cliente da vitrine de ferramentas prontas, preso à conta da URL.
describe('#AutonomiaFerramentasProntasAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };
  const BASE = '/api/v1/accounts/85/autonomia/ferramentas_prontas';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/agents');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('is an account scoped client', () => {
    expect(ferramentasProntas).toBeInstanceOf(ApiClient);
    expect(ferramentasProntas.url).toBe(BASE);
  });

  it('lists the catalog and the included tools', () => {
    ferramentasProntas.listar();
    expect(axiosMock.get).toHaveBeenCalledWith(BASE);
  });

  it('includes a tool in an agent with the "use when" sentence', () => {
    ferramentasProntas.incluir({
      fonte: 'cep',
      agenteId: 7,
      usarQuando: 'Use quando o cliente informar um CEP.',
    });
    expect(axiosMock.post).toHaveBeenCalledWith(`${BASE}/incluir`, {
      fonte: 'cep',
      agent_id: 7,
      usar_quando: 'Use quando o cliente informar um CEP.',
    });
  });

  it('turns a tool on and off and removes it', () => {
    ferramentasProntas.mudarLigada(31, false);
    expect(axiosMock.patch).toHaveBeenCalledWith(`${BASE}/31`, {
      ligada: false,
    });
    ferramentasProntas.tirar(31);
    expect(axiosMock.delete).toHaveBeenCalledWith(`${BASE}/31`);
  });

  it('tries a source and records a search without result', () => {
    ferramentasProntas.experimentar('cep', '01001-000');
    expect(axiosMock.post).toHaveBeenCalledWith(`${BASE}/experimentar`, {
      fonte: 'cep',
      valor: '01001-000',
      confirmou_preco: false,
    });
    // F7: no card Premium sem grátis, o clique no botão com o preço manda a confirmação.
    ferramentasProntas.experimentar(
      'conferir_pessoa',
      'CPF 111.444.777-35',
      true
    );
    expect(axiosMock.post).toHaveBeenCalledWith(`${BASE}/experimentar`, {
      fonte: 'conferir_pessoa',
      valor: 'CPF 111.444.777-35',
      confirmou_preco: true,
    });
    // F7: o Experimente Premium roda em segundo plano; a tela acompanha o pedido pelo id.
    ferramentasProntas.acompanhar('pedido-1');
    expect(axiosMock.get).toHaveBeenCalledWith(`${BASE}/experimentar/pedido-1`);
    ferramentasProntas.buscaSemResultado('passagem de avião');
    expect(axiosMock.post).toHaveBeenCalledWith(
      `${BASE}/buscas_sem_resultado`,
      { termo: 'passagem de avião' }
    );
  });
});
