import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import TelaInicial from '../TelaInicial.vue';
import TelaInicialResumo from '../TelaInicialResumo.vue';

// #1897 — o rodapé "Como vai o seu mês →" aparece com a mesma régua da rota de
// Números (permissão da rota + quem vê Números) e só com `crm_numeros_lentes`.
const estado = {
  flag: true,
  papel: 'agent',
  funcao: null,
  chaves: [],
  rotaAbre: true,
};

vi.mock('../useTelaInicial', () => ({ useTelaInicial: () => ({}) }));
vi.mock('dashboard/helper/routeHelpers', () => ({
  isCrmKanbanEnabled: () => true,
}));
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({
    podeAbrir: to => to.name === 'crm_dashboard_index' && estado.rotaAbre,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: chave =>
    ({
      getCurrentAccountId: ref(1),
      getCurrentUser: ref({
        accounts: [{ id: 1, permissions: estado.chaves }],
      }),
      getCurrentRole: ref(estado.papel),
      getCurrentCustomRoleId: ref(estado.funcao),
      'accounts/isFeatureEnabledonAccount': ref(() => estado.flag),
      'accounts/getAccount': ref(() => ({ id: 1, features: {} })),
    })[chave],
}));

const rodape = () =>
  shallowMount(TelaInicial)
    .findComponent(TelaInicialResumo)
    .props('comoVaiOMes');

describe('TelaInicial: rodapé "Como vai o seu mês"', () => {
  beforeEach(() => {
    Object.assign(estado, {
      flag: true,
      papel: 'agent',
      funcao: null,
      chaves: [],
      rotaAbre: true,
    });
  });

  it('agente sem função, com a flag: leva ao "Só eu"', () => {
    expect(rodape()).toEqual({
      name: 'crm_dashboard_index',
      query: { visao: 'eu' },
    });
  });

  it('sem a flag não aparece, nem para o administrador', () => {
    estado.flag = false;
    expect(rodape()).toBeNull();
    estado.papel = 'administrator';
    expect(rodape()).toBeNull();
  });

  it('função só com crm_view_reports: leva à equipe, sem "Só eu"', () => {
    Object.assign(estado, { funcao: 7, chaves: ['crm_view_reports'] });
    expect(rodape()).toEqual({ name: 'crm_dashboard_index', query: {} });
  });

  it('função só com crm_admin: não aparece, porque a rota não abre para ela', () => {
    Object.assign(estado, { funcao: 7, chaves: ['crm_admin'] });
    expect(rodape()).toBeNull();
  });

  it('função sem chave do CRM ou rota fechada: não aparece', () => {
    Object.assign(estado, { funcao: 7, chaves: ['conversation_manage'] });
    expect(rodape()).toBeNull();
    Object.assign(estado, { funcao: null, chaves: [], rotaAbre: false });
    expect(rodape()).toBeNull();
  });
});
