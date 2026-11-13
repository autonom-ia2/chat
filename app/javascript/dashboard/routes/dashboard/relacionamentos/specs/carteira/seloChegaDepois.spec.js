import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute } from 'vue-router';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ListaPage from '../../pages/ListaPage.vue';
import { daCarteira } from './apoio';

// O primeiro render da lista de pessoas na conta com a carteira (#2897), como
// acontece de verdade: a fonte da carteira e a peça do selo chegam por import()
// dinâmico, que leva tempo. As pessoas aparecem antes, e o selo entra quando os
// arquivos chegam. Este arquivo NÃO baixa nada antes (os outros testes da pasta
// baixam, no `beforeAll`, para só esperar a tela assentar): por isso é um
// arquivo só para este caso.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return {
    useAccount: () => ({
      isCloudFeatureEnabled: () => false,
      currentAccount: ref({ carteira_seguros: true }),
    }),
  };
});
vi.mock('../../lista/usePermissoesDaLista', async () => {
  const { ref } = await import('vue');
  return {
    usePermissoesDaLista: () => ({
      podeCriarCards: ref(false),
      podeEtiquetar: ref(false),
      podeApagar: ref(false),
      podeTrazer: ref(false),
    }),
  };
});
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  return {
    useRoute: () => rota,
    useRouter: () => ({ push: vi.fn() }),
  };
});
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    pessoas: vi.fn(),
    contagensDePessoas: vi.fn(),
    todasAsPessoas: vi.fn(),
    resumo: vi.fn(),
    opcoesDeFiltro: vi.fn(),
  },
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { resumoPorPessoa: vi.fn() },
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 60000 });

const rota = useRoute();
const daLista = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = 1700000000;
// O import() de verdade pode levar alguns segundos na primeira vez.
const ATE_OS_ARQUIVOS_CHEGAREM = { timeout: 30000, interval: 50 };

const pessoa = (id, name) => ({
  id,
  name,
  email: null,
  phone_number: '+5511910310001',
  thumbnail: '',
  blocked: false,
  contact_type: 'customer',
  customer_since: AGORA,
  last_activity_at: AGORA,
  created_at: AGORA,
  additional_attributes: {},
  custom_attributes: {},
  labels: [],
  opted_out_at: null,
  opt_out_source: null,
});
const DA_LISTA = {
  resumo: {
    total: 2,
    clientes: 2,
    sumiu_1_a_3_meses: 0,
    empresas: { total: 0, sem_conversa_3_meses: 0 },
  },
  contagensDePessoas: { todos: 2, clientes: 2, so_um_seguro: 1 },
  pessoas: {
    itens: [pessoa(1, 'Ana Albuquerino'), pessoa(2, 'Carla Carvalhedo')],
    total: 2,
    tem_mais: false,
  },
};
// Ana tem um seguro vencido; Carla não tem seguro.
const DOS_SEGUROS = {
  1: { quantos: 1, selo: 'vencido', tipo: 'auto', dias: -3 },
};

let aberta;
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  delete window.globalConfig;
});

describe('o primeiro render da lista de pessoas, sem nada baixado antes', () => {
  it('as pessoas aparecem logo e o selo entra quando a peça e a fonte da carteira chegam', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    Object.entries(DA_LISTA).forEach(([leitura, data]) =>
      RelacionamentosAPI[leitura].mockResolvedValue({ data })
    );
    SegurosAPI.resumoPorPessoa.mockResolvedValue({ data: DOS_SEGUROS });
    rota.query = {};

    aberta = mount(ListaPage, {
      attachTo: document.body,
      global: { stubs: { transition: true } },
    });
    await flushPromises();

    expect(aberta.findAll(daLista('linha'))).toHaveLength(2);

    await vi.waitFor(
      () => expect(aberta.findAll(daCarteira('selo'))).toHaveLength(1),
      ATE_OS_ARQUIVOS_CHEGAREM
    );
    const [ana, carla] = aberta.findAll(daLista('linha'));
    expect(ana.find(daCarteira('selo')).text()).toBe('Seguro vencido');
    expect(carla.find(daCarteira('selo')).exists()).toBe(false);
    expect(SegurosAPI.resumoPorPessoa.mock.calls).toEqual([[[1, 2]]]);
  });
});
