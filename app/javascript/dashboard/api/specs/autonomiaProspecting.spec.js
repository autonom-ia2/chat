import prospecting from '../autonomiaProspecting';
import ApiClient from '../ApiClient';

// Pedido de pesquisa de empresa e decisor (#679). O servidor responde 202 e a
// pesquisa roda em fila; force ignora o resultado guardado.
describe('#AutonomiaProspectingAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/prospecting');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('é um cliente com escopo de conta', () => {
    expect(prospecting).toBeInstanceOf(ApiClient);
    expect(prospecting).toHaveProperty('researchLead');
  });

  it('pede a pesquisa do lead sem forçar por padrão', () => {
    prospecting.researchLead(7);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/7/research',
      { force: false }
    );
  });

  it('pede a pesquisa forçada para verificar novamente', () => {
    prospecting.researchLead(7, { force: true });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/7/research',
      { force: true }
    );
  });
});
