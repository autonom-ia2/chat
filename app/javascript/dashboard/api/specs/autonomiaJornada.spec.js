import jornada from '../autonomia/jornada';
import ApiClient from '../ApiClient';

// #1181 — as duas leituras novas da jornada de Agentes (L1 e L2), no escopo da conta.
describe('#AutonomiaJornadaAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = { get: vi.fn(() => Promise.resolve()) };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/agents');
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('is an account scoped ApiClient', () => {
    expect(jornada).toBeInstanceOf(ApiClient);
  });

  it('reads the week numbers of every agent', () => {
    jornada.semana();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/numeros_da_semana',
      { params: {} }
    );
  });

  it('reads the week numbers of one agent', () => {
    jornada.semana({ agentId: 7 });
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/numeros_da_semana',
      { params: { agent_id: 7 } }
    );
  });

  it('reads who answers each inbox', () => {
    jornada.canaisOcupados();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/canais_ocupados'
    );
  });
});
