import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import CrmNumerosOrigensAPI from 'dashboard/api/crmNumerosOrigens';
import CrmNumerosOrigensPage from './CrmNumerosOrigensPage.vue';

// Números › "De onde vieram os clientes" (#2001, F6): a tela lê o servidor com o mês e o funil da URL, mostra o gasto
// só quando ele vem (em "Todos os funis", para quem vê os anúncios), convida para "Todos os funis" com um funil
// escolhido, explica a quem não vê o gasto e volta para Números sem a flag.
withFullI18n('pt_BR');

const replace = vi.fn();
const query = ref({});
vi.mock('vue-router', () => ({
  useRoute: () => ({
    get query() {
      return query.value;
    },
    params: { accountId: 1 },
  }),
  useRouter: () => ({ replace }),
}));
vi.mock('dashboard/api/crmNumerosOrigens', () => ({
  default: { show: vi.fn(), report: vi.fn() },
}));
const flagLigada = ref(true);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'accounts/isFeatureEnabledonAccount'
      ? ref((_conta, flag) =>
          flag === 'crm_numeros_origens' ? flagLigada.value : false
        )
      : ref(1),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ timezone: 'America/Sao_Paulo' }),
  }),
}));
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir: () => true }),
}));
vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('pt-BR') }),
}));
vi.mock('../components/numeros/useQuemVeNumeros', () => ({
  useQuemVeNumeros: () => ({
    pronto: ref(true),
    equipeNova: ref(true),
    veEquipe: ref(true),
  }),
}));
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canExportCrm: ref(true) }),
}));

const MES = {
  chave: '2026-10',
  fechado: false,
  diasRestantes: 11,
  anterior: '2026-09',
  seguinte: null,
};
const OPCOES = [
  { id: '1', nome: 'Vendas', principal: true },
  { id: '2', nome: 'Suporte', principal: false },
  { id: 'todos', nome: null, principal: false },
];

const resposta = (extra = {}) => ({
  vazio: false,
  mes: MES,
  moeda: 'BRL',
  valorOculto: false,
  funil: { escolhido: '1', nome: 'Vendas', opcoes: OPCOES },
  funilId: 1,
  origens: [
    { tipo: 'anuncio_meta', clientes: 18, vendas: 6, valor: 7700, lista: 19 },
    { tipo: 'direto', clientes: 9, vendas: 0, valor: 0, lista: 9 },
  ],
  anuncios: [
    {
      id: '120210000000101',
      titulo: 'Oferta da semana',
      miniatura: null,
      clientes: 8,
      vendas: 3,
      valor: 4100,
      lista: 8,
    },
  ],
  gasto: null,
  gastoOculto: false,
  gastoEmTodos: false,
  ...extra,
});

const montar = async dados => {
  CrmNumerosOrigensAPI.show.mockResolvedValue({ data: dados });
  const wrapper = mount(CrmNumerosOrigensPage, {
    global: {
      stubs: {
        OrigensComoContamos: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CrmNumerosOrigensPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    query.value = {};
    flagLigada.value = true;
  });

  it('pede o funil principal e o mês de hoje quando a URL não diz nada', async () => {
    const wrapper = await montar(resposta());

    expect(CrmNumerosOrigensAPI.show).toHaveBeenCalledWith({});
    expect(wrapper.find('[data-origem="anuncio_meta"]').exists()).toBe(true);
    expect(wrapper.find('[data-origens-destaque]').text()).toBe(
      '18 dos 27 clientes novos vieram de: Anúncio no Facebook ou Instagram.'
    );
    expect(wrapper.find('[data-origens-bloco="gasto"]').exists()).toBe(false);
  });

  it('leva o mês e o funil da URL para o servidor', async () => {
    query.value = { mes: '2026-09', funil: 'todos' };

    await montar(resposta());

    expect(CrmNumerosOrigensAPI.show).toHaveBeenCalledWith({
      mes: '2026-09',
      funil: 'todos',
    });
  });

  it('com um funil escolhido, convida para "Todos os funis" e não mostra gasto', async () => {
    const wrapper = await montar(resposta({ gastoEmTodos: true }));

    expect(wrapper.find('[data-origens-gasto-em-todos]').text()).toContain(
      'O gasto com anúncios é da conta toda. Para ver quanto custou cada venda, escolha Todos os funis.'
    );
    expect(wrapper.find('[data-anuncio-custo]').exists()).toBe(false);

    await wrapper.find('[data-ver-todos-os-funis]').trigger('click');

    expect(replace).toHaveBeenCalledWith({ query: { funil: 'todos' } });
  });

  it('em "Todos os funis" com gasto, mostra as perguntas 3 e 4', async () => {
    const wrapper = await montar(
      resposta({
        funil: { escolhido: 'todos', nome: null, opcoes: OPCOES },
        funilId: null,
        gasto: {
          total: 820,
          porCliente: 31.54,
          porVenda: 136.67,
          retorno: 9.39,
          toques: 119,
          clientes: 26,
        },
        anuncios: [
          {
            ...resposta().anuncios[0],
            gasto: 380,
            porVenda: 126.67,
          },
        ],
      })
    );

    expect(wrapper.find('[data-origens-bloco="gasto"]').exists()).toBe(true);
    expect(wrapper.find('[data-nao-mandaram]').attributes('data-toques')).toBe(
      '119'
    );
    expect(wrapper.find('[data-anuncio-custo]').text()).toContain('gastou');
    expect(wrapper.find('[data-origens-escolha-funil]').exists()).toBe(true);
  });

  it('explica a quem não pode ver o gasto', async () => {
    const wrapper = await montar(
      resposta({
        funil: { escolhido: 'todos', nome: null, opcoes: OPCOES },
        gastoOculto: true,
      })
    );

    expect(wrapper.find('[data-origens-gasto-oculto]').text()).toBe(
      'O gasto com anúncios aparece só para quem pode ver os anúncios. Peça a quem administra a conta.'
    );
  });

  it('sem valor de venda (#2075), as vendas aparecem sem R$', async () => {
    const wrapper = await montar(
      resposta({
        valorOculto: true,
        origens: [
          {
            tipo: 'anuncio_meta',
            clientes: 18,
            vendas: 6,
            valor: null,
            lista: 19,
          },
        ],
        anuncios: [{ ...resposta().anuncios[0], valor: null }],
      })
    );

    expect(wrapper.find('[data-origem="anuncio_meta"]').text()).not.toContain(
      'R$'
    );
    expect(wrapper.find('[data-anuncio]').text()).not.toContain('R$');
    expect(wrapper.find('[data-anuncio-sem-foto]').exists()).toBe(true);
  });

  it('mês vazio: a frase do funil e o seletor continua', async () => {
    const wrapper = await montar(resposta({ vazio: true, origens: [] }));

    expect(wrapper.find('[data-origens-vazio]').text()).toContain(
      'Ninguém entrou no funil Vendas em outubro.'
    );
    expect(wrapper.find('[data-origens-funil]').exists()).toBe(true);
  });

  it('volta para Números sem a flag crm_numeros_origens', async () => {
    flagLigada.value = false;

    await montar(resposta());

    expect(CrmNumerosOrigensAPI.show).not.toHaveBeenCalled();
    expect(replace).toHaveBeenCalledWith({
      name: 'crm_dashboard_index',
      params: { accountId: 1 },
    });
  });
});
