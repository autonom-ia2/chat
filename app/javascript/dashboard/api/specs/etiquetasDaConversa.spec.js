import etiquetasDaConversaAPI, {
  TEMPO_MAXIMO_MS,
} from '../etiquetasDaConversa';

describe('#EtiquetasDaConversaAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = { patch: vi.fn(() => Promise.resolve()) };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('manda só a intenção, com tempo máximo na própria chamada', () => {
    etiquetasDaConversaAPI.alterar(42, { por: ['vip'] });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/conversations/42/labels/alterar',
      { por: ['vip'], tirar: [] },
      { timeout: TEMPO_MAXIMO_MS }
    );
    expect(TEMPO_MAXIMO_MS).toBeGreaterThan(0);
  });
});
