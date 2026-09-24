// Guardas das rotas da Autonomia (#675): com link direto ou F5, o guarda roda
// antes de a conta estar na store. Sem esperar a conta, a pessoa caía em
// Conversas mesmo com o recurso ligado.
import { routes } from './autonomia.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));

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
