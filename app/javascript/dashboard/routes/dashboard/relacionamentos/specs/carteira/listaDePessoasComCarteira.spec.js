import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute } from 'vue-router';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import BarraDeControles from '../../components/lista/BarraDeControles.vue';
import ListaPage from '../../pages/ListaPage.vue';
import { daCarteira, erroHttp } from './apoio';

// A lista de pessoas na conta que tem a carteira de seguros (#2897), fora da
// demonstração: o selo de seguro ao lado do nome, o grupo "Só tem um seguro" e
// a busca que avisa que acha pela apólice. O grupo e a busca vão no pedido da
// própria lista; só o selo é uma leitura a mais, com os ids da página. Na conta
// sem a carteira a tela é a de sempre e nenhuma rota da carteira é chamada.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
// A conta aberta, como o servidor manda: `carteira_seguros` liga a carteira.
const conta = vi.hoisted(() => ({ carteira_seguros: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
    currentAccount: { value: conta },
  }),
}));
vi.mock('../../lista/usePermissoesDaLista', () => ({
  usePermissoesDaLista: () => ({
    podeCriarCards: { value: false },
    podeEtiquetar: { value: false },
    podeApagar: { value: false },
    podeTrazer: { value: false },
  }),
}));
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
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
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const daLista = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = 1700000000;

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
const ANA = pessoa(1, 'Ana Albuquerino');
const BRUNO = pessoa(2, 'Bruno Brandolim');
const CARLA = pessoa(3, 'Carla Carvalhedo');
const DA_LISTA = {
  resumo: {
    total: 3,
    clientes: 3,
    sumiu_1_a_3_meses: 0,
    empresas: { total: 0, sem_conversa_3_meses: 0 },
  },
  contagensDePessoas: { todos: 3, clientes: 3, so_um_seguro: 2 },
  pessoas: { itens: [ANA, BRUNO, CARLA], total: 3, tem_mais: false },
};
// Ana tem um seguro vencido, Bruno um ativo que vence logo; Carla não tem.
const DOS_SEGUROS = {
  1: { quantos: 2, selo: 'vencido', tipo: 'auto', dias: -3 },
  2: { quantos: 1, selo: 'ativo', tipo: 'vida', dias: 12 },
};

let aberta;
const abrir = async () => {
  rota.name = 'relationships_home';
  rota.query = {};
  aberta = mount(ListaPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await flushPromises();
  return aberta;
};
const linhas = w => w.findAll(daLista('linha'));
const seloDaLinha = linha => linha.find(daCarteira('selo'));
const grupos = w =>
  w.findAll('[data-grupo]').map(pilula => pilula.attributes('data-grupo'));
const paramsDe = metodo =>
  RelacionamentosAPI[metodo].mock.calls.map(([params]) => params);

// As peças da carteira chegam por import() dinâmico, que leva tempo de verdade:
// baixadas antes, o teste só espera a tela assentar.
beforeAll(async () => {
  await import('../../fonte/carteiraFonte');
  await import('../../components/carteira/SeloDoSeguro.vue');
}, 60000);
beforeEach(() => {
  conta.carteira_seguros = true;
  window.globalConfig = {
    CAMPAIGN_JOURNEY_ENABLED: 'true',
    CAMPAIGN_IMPORT_ENABLED: 'true',
  };
  Object.entries(DA_LISTA).forEach(([leitura, data]) =>
    RelacionamentosAPI[leitura].mockResolvedValue({ data })
  );
  SegurosAPI.resumoPorPessoa.mockResolvedValue({ data: DOS_SEGUROS });
});
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  delete window.globalConfig;
  vi.resetAllMocks();
});

describe('na conta com a carteira de seguros', () => {
  it('pede os selos só das pessoas da página, numa leitura só', async () => {
    await abrir();

    await vi.waitFor(() =>
      expect(SegurosAPI.resumoPorPessoa.mock.calls).toEqual([[[1, 2, 3]]])
    );
  });

  it('mostra o selo do seguro ao lado do nome de quem tem seguro', async () => {
    const w = await abrir();

    await vi.waitFor(() =>
      expect(w.findAll(daCarteira('selo'))).toHaveLength(2)
    );
    const [ana, bruno, carla] = linhas(w);
    expect(seloDaLinha(ana).text()).toBe('Seguro vencido');
    expect(seloDaLinha(ana).attributes('data-selo')).toBe('vermelho');
    expect(seloDaLinha(bruno).text()).toBe('Seguro ativo');
    expect(seloDaLinha(bruno).attributes('data-selo')).toBe('ambar');
    expect(seloDaLinha(carla).exists()).toBe(false);
  });

  it('tem o grupo "Só tem um seguro" depois de "Clientes", com o número que o servidor contou', async () => {
    const w = await abrir();

    expect(grupos(w).slice(0, 3)).toEqual([
      'todos',
      'clientes',
      'so_um_seguro',
    ]);
    const pilula = w.get('[data-grupo="so_um_seguro"]').text();
    expect(pilula).toContain('Só tem um seguro');
    expect(pilula).toContain('2');
  });

  it('escolher o grupo pede a lista desse grupo ao servidor e explica o grupo', async () => {
    const w = await abrir();

    await w.get('[data-grupo="so_um_seguro"]').trigger('click');
    await flushPromises();

    expect(paramsDe('pessoas').at(-1)).toMatchObject({
      grupo: 'so_um_seguro',
    });
    expect(w.get(daLista('explicacao-do-grupo')).text()).toBe(
      'Quem tem só um seguro ativo. Boa hora para oferecer outro.'
    );
  });

  it('o campo de busca diz que acha pela apólice', async () => {
    const w = await abrir();

    expect(w.getComponent(BarraDeControles).props('placeholder')).toBe(
      'Buscar por nome, telefone, documento ou apólice'
    );
  });

  it.each([500, 404, 401])(
    'com a carteira respondendo %i, a lista aparece inteira, sem selo e sem erro',
    async status => {
      SegurosAPI.resumoPorPessoa.mockRejectedValue(erroHttp(status));

      const w = await abrir();
      await vi.waitFor(() =>
        expect(SegurosAPI.resumoPorPessoa).toHaveBeenCalledTimes(1)
      );
      await flushPromises();

      expect(linhas(w)).toHaveLength(3);
      expect(w.find(daCarteira('selo')).exists()).toBe(false);
      expect(w.find(daLista('erro')).exists()).toBe(false);
    }
  );
});

describe('na conta sem a carteira de seguros', () => {
  beforeEach(() => {
    conta.carteira_seguros = false;
    RelacionamentosAPI.contagensDePessoas.mockResolvedValue({
      data: { todos: 3, clientes: 3 },
    });
  });

  it('a lista é a de sempre e nenhuma rota da carteira é chamada', async () => {
    const w = await abrir();
    await flushPromises();

    expect(linhas(w)).toHaveLength(3);
    expect(SegurosAPI.resumoPorPessoa).not.toHaveBeenCalled();
    expect(w.find('[data-carteira]').exists()).toBe(false);
    expect(w.find('[data-grupo="so_um_seguro"]').exists()).toBe(false);
    expect(w.getComponent(BarraDeControles).props('placeholder')).toBe(
      'Buscar por nome, telefone ou documento'
    );
  });
});
