import { createRouter, createMemoryHistory } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { validateLoggedInRoutes } from 'dashboard/helper/routeHelpers';
import settingsRoutes from '../settings.routes';

// /settings em carregamento frio (endereço digitado ou F5, #1617): o usuário e a conta chegam DEPOIS que a
// navegação começa. O guarda global do app espera o usuário e confere o `meta.permissions` da rota
// (validateLoggedInRoutes, o mesmo de routes/index.js); a conta chega pelo `accounts/get`. Antes, o
// settings_home decidia num `redirect` síncrono, com a store ainda vazia, e quebrava em `landing.name`.
const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../store', () => ({ default: store }));

const vazio = { render: () => null };
const CONTA = 9;

const montarRouter = ({ conta, menuNovo, contaFalha = false }) => {
  const usuario = { accounts: [{ id: CONTA, status: 'active', ...conta }] };
  // Store vazia, como no F5: nada de usuário nem de conta. Os getters existem e respondem "sem conta".
  let contaCarregada = false;
  store.getters = {
    'accounts/getAccount': id =>
      contaCarregada && id === CONTA ? { id } : undefined,
    'accounts/isFeatureEnabledonAccount': (id, flag) =>
      contaCarregada &&
      id === CONTA &&
      menuNovo &&
      flag === 'menu_lateral_novo',
  };
  // accounts/get de verdade engole o erro: quando falha, a conta só não chega.
  store.dispatch = vi.fn(async acao => {
    if (acao === 'accounts/get' && !contaFalha) contaCarregada = true;
  });

  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: frontendURL('accounts/:accountId/dashboard'),
        name: 'home',
        // O que interessa aqui é chegar no dashboard; a permissão da própria tela fica fora deste teste.
        meta: { permissions: ['administrator', 'agent', 'custom_role'] },
        component: vazio,
      },
      ...settingsRoutes.routes,
    ],
  });
  // O guarda global do app (routes/index.js): espera o usuário e confere a permissão da rota.
  router.beforeEach(async to => {
    await Promise.resolve();
    // Só o usuário: o getCurrentRole do app lê a rota atual, que no carregamento frio ainda não tem conta.
    Object.assign(store.getters, {
      getCurrentUser: usuario,
      getCurrentRole: undefined,
      getCurrentCustomRoleId: undefined,
    });
    const desvio = validateLoggedInRoutes(to, usuario);
    return desvio ? frontendURL(desvio) : true;
  });
  return router;
};

const abrirConfiguracoes = async opcoes => {
  const router = montarRouter(opcoes);
  await router.push(frontendURL(`accounts/${CONTA}/settings`));
  return router.currentRoute.value;
};

const DASHBOARD = `/app/accounts/${CONTA}/dashboard`;
const ADMIN = {
  role: 'administrator',
  custom_role_id: null,
  permissions: ['administrator'],
};
const AGENTE = { role: 'agent', custom_role_id: null, permissions: ['agent'] };
const FUNCAO = {
  role: 'agent',
  custom_role_id: 7,
  permissions: ['custom_role', 'label_manage'],
};
const SO_CRM = {
  role: 'agent',
  custom_role_id: 7,
  permissions: ['custom_role', 'crm_manage_ai'],
};

describe('/settings em carregamento frio', () => {
  it('administrador, menu novo desligado: Conta', async () => {
    const rota = await abrirConfiguracoes({ conta: ADMIN, menuNovo: false });
    expect(rota.name).toBe('general_settings_index');
  });

  it('administrador, menu novo ligado: página de cartões', async () => {
    const rota = await abrirConfiguracoes({ conta: ADMIN, menuNovo: true });
    expect(rota.name).toBe('settings_inicio');
  });

  it('administrador sem custom_role_id no payload (build sem EE): Conta', async () => {
    const { custom_role_id: _semFuncao, ...semCampo } = ADMIN;
    const rota = await abrirConfiguracoes({ conta: semCampo, menuNovo: false });
    expect(rota.name).toBe('general_settings_index');
  });

  it('agente comum sem função: Respostas prontas sem a flag, cartões com ela', async () => {
    expect(
      (await abrirConfiguracoes({ conta: AGENTE, menuNovo: false })).name
    ).toBe('canned_list');
    expect(
      (await abrirConfiguracoes({ conta: AGENTE, menuNovo: true })).name
    ).toBe('settings_inicio');
  });

  it('função personalizada, menu novo desligado: a primeira tela que ela abre', async () => {
    const rota = await abrirConfiguracoes({ conta: FUNCAO, menuNovo: false });
    expect(rota.name).toBe('labels_list');
  });

  it('função personalizada, menu novo ligado: página de cartões', async () => {
    const rota = await abrirConfiguracoes({ conta: FUNCAO, menuNovo: true });
    expect(rota.name).toBe('settings_inicio');
  });

  it('só chaves do CRM: o guarda global deixa entrar; cartões com a flag, dashboard sem ela', async () => {
    expect(
      (await abrirConfiguracoes({ conta: SO_CRM, menuNovo: true })).name
    ).toBe('settings_inicio');
    expect(
      (await abrirConfiguracoes({ conta: SO_CRM, menuNovo: false })).fullPath
    ).toBe(DASHBOARD);
  });

  it('sem nenhuma permissão de Configurações: o guarda global manda para o dashboard', async () => {
    const rota = await abrirConfiguracoes({
      conta: { role: 'agent', custom_role_id: 7, permissions: ['custom_role'] },
      menuNovo: false,
    });
    expect(rota.fullPath).toBe(DASHBOARD);
  });

  it('accounts/get falha: não quebra e segue a regra de sempre (sem a flag)', async () => {
    const rota = await abrirConfiguracoes({
      conta: ADMIN,
      menuNovo: true,
      contaFalha: true,
    });
    expect(rota.name).toBe('general_settings_index');
  });
});
