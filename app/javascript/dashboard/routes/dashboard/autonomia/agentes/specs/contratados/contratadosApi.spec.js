import ContratadosAPI from 'dashboard/api/autonomia/contratados';
import ApiClient from 'dashboard/api/ApiClient';

// #3211 (Tarefa 25) — o cliente da API dos agentes prontos que a pessoa contrata (Tarefa 21), no escopo da conta.
describe('ContratadosAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve({ data: {} })),
    post: vi.fn(() => Promise.resolve({ data: { estado: 'ok' } })),
    patch: vi.fn(() => Promise.resolve({ data: {} })),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    window.history.pushState({}, '', '/app/accounts/85/agents');
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('is an account scoped ApiClient', () => {
    expect(ContratadosAPI).toBeInstanceOf(ApiClient);
  });

  it('lists the hired models of the account', () => {
    ContratadosAPI.lista();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/contratados'
    );
  });

  it('hires a model sending the three fields in snake_case', () => {
    ContratadosAPI.contratar('seguro_viagem_universal', {
      nomeAgente: 'Bia',
      nomeCorretora: 'Corretora Exemplo',
      sobreCorretora: 'Corretora em Campinas desde 2010.',
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/contratados/seguro_viagem_universal',
      {
        nome_agente: 'Bia',
        nome_corretora: 'Corretora Exemplo',
        sobre_corretora: 'Corretora em Campinas desde 2010.',
      }
    );
  });

  it('saves only the fields it was given, in snake_case', () => {
    ContratadosAPI.salvarDados(7, { nomeCorretora: 'Corretora Nova' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/7/contratado',
      { nome_corretora: 'Corretora Nova' }
    );
  });

  it('saves the three fields together', () => {
    ContratadosAPI.salvarDados(7, {
      nomeAgente: 'Bia',
      nomeCorretora: 'Corretora Exemplo',
      sobreCorretora: '',
    });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/7/contratado',
      {
        nome_agente: 'Bia',
        nome_corretora: 'Corretora Exemplo',
        sobre_corretora: '',
      }
    );
  });

  it('reads the access state of one agent', () => {
    ContratadosAPI.acesso(7);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/7/acesso_da_seguradora'
    );
  });

  it('checks the access posting login and password exactly', () => {
    ContratadosAPI.conferirAcesso(7, {
      login: 'corretora.exemplo',
      senha: 'senha-de-teste',
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/agents/7/acesso_da_seguradora',
      { login: 'corretora.exemplo', senha: 'senha-de-teste' }
    );
  });

  it('never keeps the password after the POST', async () => {
    const senha = 'senha-que-nao-pode-ficar';
    await ContratadosAPI.conferirAcesso(7, { login: 'corretora.exemplo', senha });

    const guardado = JSON.stringify({ ...ContratadosAPI });
    expect(guardado).not.toContain(senha);
    expect(JSON.stringify(axiosMock.get.mock.calls)).not.toContain(senha);
  });
});
