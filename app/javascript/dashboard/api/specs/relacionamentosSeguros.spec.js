import axios from 'axios';
import seguros from '../relacionamentosSeguros';
import ApiClient from '../ApiClient';

// A carteira de seguros de Relacionamentos (#2897): a leitura que a lista de
// pessoas faz para pôr o selo de seguro ao lado de cada nome.
describe('#RelacionamentosSegurosAPI', () => {
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
    expect(seguros).toBeInstanceOf(ApiClient);
    expect(seguros.url).toBe(BASE);
  });

  it('resumoPorPessoa manda só os ids da página, em `pessoa_ids`', () => {
    seguros.resumoPorPessoa([7, 8, 9]);

    expect(axiosMock.get).toHaveBeenCalledWith(
      `${BASE}/seguros/resumo_por_dono`,
      { params: { pessoa_ids: [7, 8, 9] } }
    );
  });

  // O servidor só aceita a lista como `pessoa_ids[]=7&pessoa_ids[]=8`: é como
  // o axios do painel escreve uma lista, e aqui o endereço é montado por ele.
  it('no endereço, cada id vai num `pessoa_ids[]`', () => {
    seguros.resumoPorPessoa([7, 8, 9]);

    const [url, pedido] = axiosMock.get.mock.calls[0];
    const endereco = new URL(
      axios.getUri({ url, ...pedido }),
      'https://painel.exemplo'
    );

    expect(endereco.pathname).toBe(`${BASE}/seguros/resumo_por_dono`);
    expect([...endereco.searchParams.keys()]).toEqual([
      'pessoa_ids[]',
      'pessoa_ids[]',
      'pessoa_ids[]',
    ]);
    expect(endereco.searchParams.getAll('pessoa_ids[]')).toEqual([
      '7',
      '8',
      '9',
    ]);
  });
});
