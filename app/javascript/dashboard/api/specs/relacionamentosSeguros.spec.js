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
});
