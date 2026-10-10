// Guardas das rotas da Autonomia (#675): com link direto ou F5, o guarda roda
// antes de a conta estar na store. Sem esperar a conta, a pessoa caía em
// Conversas mesmo com o recurso ligado.
import { routes } from './autonomia.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));

// #1181: a lista de agentes passa por um seletor fino que decide pela flag.
vi.mock('./agentes/entrada/AgentesListaEntrada.vue', () => ({
  default: { name: 'AgentesListaEntrada' },
}));
// #1181: a criação e a página do agente também passam por seletores, com a mesma regra.
vi.mock('./agentes/entrada/AgentesCriarEntrada.vue', () => ({
  default: { name: 'AgentesCriarEntrada' },
}));
vi.mock('./agentes/entrada/AgentePaginaEntrada.vue', () => ({
  default: { name: 'AgentePaginaEntrada' },
}));

const rota = name => routes.find(route => route.name === name);
const entrar = async name => {
  const next = vi.fn();
  await rota(name).beforeEnter({ params: { accountId: '9' } }, {}, next);
  return next;
};

// A store começa sem a conta (link direto) e só a tem depois de accounts/get.
const contaCarregaDepois = conta => {
  let carregada = null;
  store.getters['accounts/getAccount'] = () => carregada;
  store.dispatch.mockImplementation(async () => {
    carregada = conta;
  });
};

describe('guardas da Autonomia com link direto', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    window.globalConfig = {
      AUTONOMIA_AGENTS_ENABLED: 'true',
      INSURANCE_QUOTING_ENABLED: 'true',
    };
  });

  it.each([
    'autonomia_prospecting_search',
    'autonomia_prospecting_lists',
    'autonomia_prospecting_settings',
  ])('Prospecção (%s) espera a conta e entra', async name => {
    contaCarregaDepois({ id: 9, autonomia_prospecting_enabled: true });
    const next = await entrar(name);
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  it('Agentes esperam a conta e entram', async () => {
    contaCarregaDepois({ id: 9, autonomia_agents_enabled: true });
    const next = await entrar('autonomia_agents_index');
    expect(next).toHaveBeenCalledWith();
  });

  it('Cotação continua esperando a conta e entrando', async () => {
    contaCarregaDepois({ id: 9, autonomia_insurance_enabled: true });
    const next = await entrar('autonomia_insurance');
    expect(next).toHaveBeenCalledWith();
  });

  it('com a conta já na store, não busca de novo', async () => {
    store.getters['accounts/getAccount'] = () => ({
      id: 9,
      autonomia_prospecting_enabled: true,
    });
    const next = await entrar('autonomia_prospecting_search');
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith();
  });

  it('recurso desligado na conta continua indo para home', async () => {
    contaCarregaDepois({ id: 9, autonomia_prospecting_enabled: false });
    const next = await entrar('autonomia_prospecting_search');
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('conta que não carrega vai para home, sem erro', async () => {
    store.getters['accounts/getAccount'] = () => null;
    store.dispatch.mockRejectedValue(new Error('rede'));
    const next = await entrar('autonomia_prospecting_search');
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });
});

// #1181: só os componentes da lista, da criação e da página do agente mudam (seletores);
// nome, caminho, meta, guarda e props continuam os mesmos.
describe('entrada da lista de agentes (#1181)', () => {
  it('a rota da lista abre o seletor, com o mesmo caminho, meta e guarda', async () => {
    const lista = rota('autonomia_agents_index');
    const { default: componente } = await lista.component();

    expect(componente.name).toBe('AgentesListaEntrada');
    expect(lista.path).toBe('/app/accounts/:accountId/agents');
    expect(lista.meta).toEqual({
      permissions: ['administrator', 'autonomia_view', 'autonomia_manage'],
    });
    expect(lista.beforeEnter).toBe(rota('autonomia_agent_panel').beforeEnter);
  });

  it('a rota do Construtor abre o seletor da criação, com o mesmo caminho, meta e guarda', async () => {
    const construtor = rota('autonomia_agents_builder');
    const { default: componente } = await construtor.component();

    expect(componente.name).toBe('AgentesCriarEntrada');
    expect(construtor.path).toBe('/app/accounts/:accountId/agents/new');
    expect(construtor.meta).toEqual({
      permissions: ['administrator', 'autonomia_manage'],
    });
    expect(construtor.beforeEnter).toBe(
      rota('autonomia_agent_panel').beforeEnter
    );
    expect(construtor.props).toBeUndefined();
  });

  it('o Construtor continua barrando quem não tem o módulo ligado', async () => {
    window.globalConfig = { AUTONOMIA_AGENTS_ENABLED: 'true' };
    store.dispatch.mockReset();
    contaCarregaDepois({ id: 9, autonomia_agents_enabled: false });
    const next = await entrar('autonomia_agents_builder');
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('o Construtor e a página do agente continuam com o mesmo caminho, meta e props', () => {
    const construtor = rota('autonomia_agents_builder');
    const painel = rota('autonomia_agent_panel');

    expect(construtor.path).toBe('/app/accounts/:accountId/agents/new');
    expect(construtor.meta).toEqual({
      permissions: ['administrator', 'autonomia_manage'],
    });
    expect(painel.props({ params: { agentId: '7' } })).toEqual({
      agentId: '7',
      tab: 'test',
    });
    expect(painel.props({ params: { agentId: '7', tab: 'channels' } })).toEqual(
      { agentId: '7', tab: 'channels' }
    );
  });

  it('a página do agente abre o seletor, com o mesmo caminho, meta, guarda e props', async () => {
    const painel = rota('autonomia_agent_panel');
    const { default: componente } = await painel.component();

    expect(componente.name).toBe('AgentePaginaEntrada');
    expect(painel.path).toBe(
      '/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?'
    );
    expect(painel.meta).toEqual({
      permissions: ['administrator', 'autonomia_view', 'autonomia_manage'],
    });
    expect(painel.beforeEnter).toBe(rota('autonomia_agents_index').beforeEnter);
  });

  it.each(['test', 'knowledge', 'channels', 'performance', 'tune', 'publish'])(
    'a aba antiga %s continua chegando ao seletor pelo props',
    tab => {
      expect(
        rota('autonomia_agent_panel').props({ params: { agentId: '7', tab } })
      ).toEqual({ agentId: '7', tab });
    }
  );

  it('a página do agente entra pela mesma guarda de Agentes', async () => {
    contaCarregaDepois({ id: 9, autonomia_agents_enabled: true });
    window.globalConfig = { AUTONOMIA_AGENTS_ENABLED: 'true' };
    const next = await entrar('autonomia_agent_panel');
    expect(next).toHaveBeenCalledWith();
  });
});
