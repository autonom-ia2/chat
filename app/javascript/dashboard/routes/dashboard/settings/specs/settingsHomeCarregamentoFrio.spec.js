import { createRouter, createMemoryHistory } from 'vue-router';
import settingsRoutes from '../settings.routes';

// /settings em carregamento frio (endereço digitado ou F5, #1617): o usuário e a conta chegam DEPOIS que a
// navegação começa. O guarda global do app espera o usuário; a conta chega pelo `accounts/get`. Antes, o
// settings_home decidia num `redirect` síncrono, com a store ainda vazia, e quebrava em `landing.name`.
const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../store', () => ({ default: store }));

const vazio = { render: () => null };
const CONTA = 9;

const montarRouter = ({ papel, funcao, chaves, menuNovo }) => {
  const usuario = {
    accounts: [
      { id: CONTA, role: papel, custom_role_id: funcao, permissions: chaves },
    ],
  };
  // Store vazia, como no F5: nada de usuário nem de conta.
  store.getters = {};
  store.dispatch = vi.fn(async acao => {
    if (acao !== 'accounts/get') return;
    store.getters['accounts/getAccount'] = id => ({ id });
    store.getters['accounts/isFeatureEnabledonAccount'] = (id, flag) =>
      id === CONTA && menuNovo && flag === 'menu_lateral_novo';
  });
  store.getters['accounts/getAccount'] = () => undefined;

  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/dashboard',
        name: 'home',
        component: vazio,
      },
      ...settingsRoutes.routes,
    ],
  });
  // O guarda global do app (routes/index.js) espera o usuário antes de seguir.
  router.beforeEach(async () => {
    await Promise.resolve();
    // Só o usuário: o getCurrentRole do app lê a rota atual, que no carregamento frio ainda não tem conta.
    Object.assign(store.getters, {
      getCurrentUser: usuario,
      getCurrentRole: undefined,
      getCurrentCustomRoleId: undefined,
    });
  });
  return router;
};

const abrirConfiguracoes = async opcoes => {
  const router = montarRouter(opcoes);
  await router.push(`/app/accounts/${CONTA}/settings`);
  return router.currentRoute.value;
};

const ADMIN = {
  papel: 'administrator',
  funcao: null,
  chaves: ['administrator'],
};
const FUNCAO = {
  papel: 'agent',
  funcao: 7,
  chaves: ['custom_role', 'label_manage'],
};

describe('/settings em carregamento frio', () => {
  it('administrador, menu novo desligado: Conta', async () => {
    const rota = await abrirConfiguracoes({ ...ADMIN, menuNovo: false });
    expect(rota.name).toBe('general_settings_index');
  });

  it('administrador, menu novo ligado: página de cartões', async () => {
    const rota = await abrirConfiguracoes({ ...ADMIN, menuNovo: true });
    expect(rota.name).toBe('settings_inicio');
  });

  it('função personalizada, menu novo desligado: a primeira tela que ela abre', async () => {
    const rota = await abrirConfiguracoes({ ...FUNCAO, menuNovo: false });
    expect(rota.name).toBe('labels_list');
  });

  it('função personalizada, menu novo ligado: página de cartões', async () => {
    const rota = await abrirConfiguracoes({ ...FUNCAO, menuNovo: true });
    expect(rota.name).toBe('settings_inicio');
  });

  it('sem nenhuma tela de Configurações permitida: destino seguro, sem quebrar', async () => {
    const rota = await abrirConfiguracoes({
      papel: 'agent',
      funcao: 7,
      chaves: ['custom_role'],
      menuNovo: false,
    });
    expect(rota.fullPath).toBe(`/app/accounts/${CONTA}/dashboard`);
  });
});
