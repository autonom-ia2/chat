import agents from '../autonomia/agents';
import buildThreads from '../autonomia/buildThreads';

describe('Contratos da criação de agentes', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/agents/new');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('abre o rascunho com o contrato assíncrono da Escolha', () => {
    buildThreads.create({
      type: 'support',
      actuation: 'external',
      with_knowledge: true,
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/build_threads',
      expect.objectContaining({
        type: 'support',
        actuation: 'external',
        with_knowledge: true,
      })
    );
    expect(axiosMock.post.mock.calls[0][1]).not.toHaveProperty('name');
    expect(axiosMock.post.mock.calls[0][1]).not.toHaveProperty('greeting');
  });

  it('publica um agente externo sem enviar campos editados no Teste', () => {
    agents.publish(42, {
      inboxId: 8,
      responseWindow: 'business_hours',
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/42/publish',
      {
        inbox_id: 8,
        agent: { config: { response_window: 'business_hours' } },
      }
    );
    expect(axiosMock.post.mock.calls[0][1]).not.toHaveProperty('name');
    expect(axiosMock.post.mock.calls[0][1]).not.toHaveProperty('greeting');
  });

  it('publica duas caixas no mesmo pedido sem alterar a apresentação', () => {
    agents.publish(42, { inboxIds: [8, 9], responseWindow: 'business_hours' });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/42/publish',
      {
        inbox_ids: [8, 9],
        agent: { config: { response_window: 'business_hours' } },
      }
    );
  });

  it('publica um agente interno sem criar uma associação de caixa', () => {
    agents.publish(43, { responseWindow: 'always' });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/43/publish',
      { agent: { config: { response_window: 'always' } } }
    );
  });
});
