// Guardas das rotas da Autonomia (#675): com link direto ou F5, o guarda roda
// antes de a conta estar na store. Sem esperar a conta, a pessoa caía em
// Conversas mesmo com o recurso ligado.
import { createMemoryHistory, createRouter } from 'vue-router';
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

// #2226 — o painel de desempenho do agente: rota própria (não é uma aba do :tab), com a nova
// jornada e a flag agentes_painel_desempenho na conta. Sem uma das duas, vai para home.
describe('painel de desempenho (#2226)', () => {
  const ligada = {
    id: 9,
    autonomia_agents_enabled: true,
    features: {
      autonomia_agents_journey: true,
      agentes_painel_desempenho: true,
    },
  };

  beforeEach(() => {
    store.dispatch.mockReset();
    window.globalConfig = { AUTONOMIA_AGENTS_ENABLED: 'true' };
  });

  it('tem caminho próprio, a chave desempenho_view (#2251) e o id pelo props', () => {
    const desempenho = rota('autonomia_agent_desempenho');
    expect(desempenho.path).toBe(
      '/app/accounts/:accountId/agents/:agentId/desempenho'
    );
    expect(desempenho.meta).toEqual({
      permissions: ['administrator', 'desempenho_view'],
    });
    expect(desempenho.props({ params: { agentId: '7' } })).toEqual({
      agentId: '7',
    });
  });

  it('entra com a jornada e a flag ligadas, esperando a conta', async () => {
    contaCarregaDepois(ligada);
    const next = await entrar('autonomia_agent_desempenho');
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  it.each([
    ['sem a flag', { ...ligada, features: { autonomia_agents_journey: true } }],
    [
      'sem a nova jornada',
      { ...ligada, features: { agentes_painel_desempenho: true } },
    ],
    ['com Agentes desligado', { ...ligada, autonomia_agents_enabled: false }],
  ])('%s vai para home', async (_caso, conta) => {
    contaCarregaDepois(conta);
    const next = await entrar('autonomia_agent_desempenho');
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('com o ENV master desligado vai para home sem buscar a conta', async () => {
    window.globalConfig = { AUTONOMIA_AGENTS_ENABLED: 'false' };
    const next = await entrar('autonomia_agent_desempenho');
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });
});

// #3211 (Tarefa 29a) — a página do agente pronto que a pessoa contrata. Tem de vir antes da página do agente, para
// `prontos` não casar como `:agentId`, e só abre com a flag da conta.
describe('página do modelo contratado (#3211)', () => {
  const FLAG = 'agente_seguro_viagem_universal';
  const contaCom = features => ({
    id: 9,
    autonomia_agents_enabled: true,
    features,
  });
  const ligadaNa = (_contaId, flag) => store.getters.flags.includes(flag);
  // Roda os guardas da rota em fila, como o vue-router, parando no primeiro que desvia.
  const entrarEmFila = async name => {
    const guardas = [].concat(rota(name).beforeEnter);
    const chamadas = [];
    let desviou = false;
    for (let i = 0; i < guardas.length && !desviou; i += 1) {
      const next = vi.fn();
      // eslint-disable-next-line no-await-in-loop
      await guardas[i]({ params: { accountId: '9' } }, {}, next);
      chamadas.push(next.mock.calls[0]);
      desviou = next.mock.calls[0].length > 0;
    }
    return chamadas;
  };

  beforeEach(() => {
    store.dispatch.mockReset();
    window.globalConfig = { AUTONOMIA_AGENTS_ENABLED: 'true' };
    store.getters.flags = [FLAG];
    store.getters['accounts/isFeatureEnabledonAccount'] = ligadaNa;
    store.getters['accounts/getAccount'] = () => contaCom({ [FLAG]: true });
  });

  it('tem o caminho, o id do modelo pelo props e a chave de gerenciar com a flag', () => {
    const contratado = rota('autonomia_contratado_modelo');
    expect(contratado.path).toBe(
      '/app/accounts/:accountId/agents/prontos/:modelo'
    );
    expect(contratado.meta).toEqual({
      permissions: ['administrator', 'autonomia_manage'],
      featureFlag: FLAG,
    });
    expect(
      contratado.props({ params: { modelo: 'seguro_viagem_universal' } })
    ).toEqual({ modelo: 'seguro_viagem_universal' });
  });

  it('vem antes da página do agente na lista de rotas', () => {
    const nomes = routes.map(route => route.name);
    expect(nomes.indexOf('autonomia_contratado_modelo')).toBeGreaterThan(-1);
    expect(nomes.indexOf('autonomia_contratado_modelo')).toBeLessThan(
      nomes.indexOf('autonomia_agent_panel')
    );
  });

  it('o roteador resolve prontos/:modelo para a rota do modelo, e não para um agente', () => {
    const roteador = createRouter({
      history: createMemoryHistory(),
      routes,
    });
    const resolvida = roteador.resolve(
      '/app/accounts/9/agents/prontos/seguro_viagem_universal'
    );
    expect(resolvida.name).toBe('autonomia_contratado_modelo');
    expect(resolvida.params.modelo).toBe('seguro_viagem_universal');
    expect(roteador.resolve('/app/accounts/9/agents/7').name).toBe(
      'autonomia_agent_panel'
    );
  });

  it('entra com Agentes ligado e a flag ligada na conta', async () => {
    const chamadas = await entrarEmFila('autonomia_contratado_modelo');
    expect(chamadas).toEqual([[], []]);
  });

  it('com a flag desligada vai para home', async () => {
    store.getters.flags = [];
    const chamadas = await entrarEmFila('autonomia_contratado_modelo');
    expect(chamadas.at(-1)).toEqual([
      { name: 'home', params: { accountId: '9' } },
    ]);
  });

  it('com Agentes desligado na conta vai para home, antes de olhar a flag', async () => {
    store.getters['accounts/getAccount'] = () => ({
      id: 9,
      autonomia_agents_enabled: false,
    });
    const chamadas = await entrarEmFila('autonomia_contratado_modelo');
    expect(chamadas).toEqual([[{ name: 'home', params: { accountId: '9' } }]]);
  });
});
