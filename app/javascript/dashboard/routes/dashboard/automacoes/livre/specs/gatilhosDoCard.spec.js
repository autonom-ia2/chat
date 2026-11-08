import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';
import { useGatilhosNovos } from '../useGatilhosNovos';
import { fraseDoGatilho } from '../frases';
import { useEscolhasDosGatilhos } from '../useEscolhasDosGatilhos';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2499 — os gatilhos de card do funil no editor: só com a flag e para quem
// pode mexer no funil; a etapa é obrigatória e vai como etapa_id; sem funil
// escolhido, funil_id não vai; a frase diz o nome da etapa.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const permissao = vi.hoisted(() => ({ funil: true }));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({
        canManagePipelines: computed(() => permissao.funil),
      }),
    };
  }
);
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 3, name: 'Vendas' }] } })
    ),
    getStages: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 12, name: 'Orçamento' }] } })
    ),
  },
}));

const parametro = (nome, peca, obrigatorio) => ({
  nome,
  peca,
  obrigatorio,
  frase: `AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.${nome.toUpperCase()}`,
});
const deCard = (tipo, chave, parametros) => ({
  tipo,
  alvo: 'Crm::Card',
  frase: `AUTOMACAO_LIVRE.GATILHOS.${chave}`,
  grupo: 'card',
  requer: 'automacao_gatilhos',
  funil: true,
  parametros,
});
const CATALOGO = {
  gatilhos: [
    {
      tipo: 'conversa.criada',
      alvo: 'Conversation',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CONVERSA_CRIADA',
      grupo: 'conversa',
    },
    deCard('card.entrou_na_etapa', 'CARD_ENTROU_NA_ETAPA', [
      parametro('etapa_id', 'etapa', true),
    ]),
    deCard('card.ganho', 'CARD_GANHO', [parametro('funil_id', 'funil', false)]),
  ],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [],
};

// Os gatilhos que o editor oferece, numa tela mínima.
const oferecidos = async (flags, catalogo = CATALOGO) => {
  let resultado;
  mount({
    setup() {
      resultado = useGatilhosNovos(flag => flags.includes(flag), ref(catalogo));
      return {};
    },
    template: '<div />',
  });
  await flushPromises();
  return resultado;
};
const tipos = lista => lista.map(item => item.tipo);

const ESCOLHAS = {
  funis: [{ value: 3, label: 'Vendas' }],
  etapas: [{ label: 'Vendas', options: [{ value: 12, label: 'Orçamento' }] }],
  nomes: {
    funil: { 3: 'Vendas' },
    etapa: { 12: 'Orçamento' },
    funilDaEtapa: {},
  },
};
const PainelFalso = {
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
};
const montar = () =>
  mount(LivreAlterar, {
    props: {
      catalogo: CATALOGO,
      opcoes: {},
      atributosDaPeca: () => [],
      atributosDo: () => [],
      gatilhos: CATALOGO.gatilhos,
      escolhasDoGatilho: ESCOLHAS,
    },
    global: {
      stubs: { SidePanel: PainelFalso },
      mocks: { $t: chave => chave },
    },
  });
const seletores = wrapper =>
  wrapper.findAllComponents({ name: 'ChoiceSelect' });
const escolher = async (seletor, valor) => {
  seletor.vm.$emit('update:modelValue', valor);
  await flushPromises();
};
const salvarDesligado = wrapper =>
  wrapper.find('[data-salvar]').attributes('disabled') !== undefined;

describe('gatilhos de card', () => {
  beforeEach(() => {
    permissao.funil = true;
  });

  it('só oferece os de card com a flag e a chave de funis', async () => {
    expect(tipos((await oferecidos([])).gatilhos.value)).toEqual([
      'conversa.criada',
    ]);

    permissao.funil = false;
    expect(
      tipos((await oferecidos(['automacao_gatilhos'])).gatilhos.value)
    ).toEqual(['conversa.criada']);

    permissao.funil = true;
    const comTudo = await oferecidos(['automacao_gatilhos']);
    expect(tipos(comTudo.gatilhos.value)).toEqual([
      'conversa.criada',
      'card.entrou_na_etapa',
      'card.ganho',
    ]);
    // E aí lê os funis e as etapas, agrupadas pelo funil.
    expect(comTudo.escolhasDoGatilho.value.etapas).toEqual(ESCOLHAS.etapas);
    // Sem gatilho de data oferecido, os campos de data não são lidos.
    expect(comTudo.escolhasDoGatilho.value.nomes).toEqual({
      ...ESCOLHAS.nomes,
      campo: { 'Crm::Card': {}, Contact: {} },
    });
  });

  it('o de reunião só com as reuniões da instalação ligadas', async () => {
    const comReuniao = {
      ...CATALOGO,
      gatilhos: [
        ...CATALOGO.gatilhos,
        {
          ...deCard('card.reuniao_marcada', 'CARD_REUNIAO_MARCADA', []),
          grupo: 'reuniao',
          reunioes: true,
        },
      ],
    };
    const ofertados = async () =>
      tipos(
        (await oferecidos(['automacao_gatilhos'], comReuniao)).gatilhos.value
      );

    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    expect(await ofertados()).not.toContain('card.reuniao_marcada');

    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    expect(await ofertados()).toContain('card.reuniao_marcada');
    window.globalConfig = {};
  });

  it('o seletor agrupa conversa e card', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({ tipo: 'gatilho', valor: null });
    await flushPromises();
    expect(
      seletores(wrapper)[0]
        .props('groups')
        .map(grupo => grupo.label)
    ).toEqual([
      'AUTOMACAO_LIVRE.GRUPOS_DO_GATILHO.CONVERSA',
      'AUTOMACAO_LIVRE.GRUPOS_DO_GATILHO.CARD',
    ]);
  });

  it('"entrou na etapa" pede a etapa e a grava como etapa_id', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({ tipo: 'gatilho', valor: null });
    await flushPromises();
    await escolher(seletores(wrapper)[0], 'card.entrou_na_etapa');

    expect(wrapper.find('[data-parametro="etapa_id"]').exists()).toBe(true);
    expect(wrapper.find('[data-nao-dispara]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(true);

    const etapa = seletores(wrapper)[1];
    expect(etapa.props('groups')).toEqual(ESCOLHAS.etapas);
    await escolher(etapa, 12);
    expect(salvarDesligado(wrapper)).toBe(false);
    expect(wrapper.find('[data-frase-alterar]').text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA Orçamento'
    );

    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor).toMatchObject({
      tipo: 'card.entrou_na_etapa',
      etapa_id: 12,
    });
  });

  it('"card ganho" sem funil não grava funil_id', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({
      tipo: 'gatilho',
      valor: { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
    });
    await flushPromises();
    await escolher(seletores(wrapper)[0], 'card.ganho');
    expect(wrapper.find('[data-nao-dispara]').exists()).toBe(false);
    expect(salvarDesligado(wrapper)).toBe(false);

    // Escolher um funil e voltar para "Todos os funis" tira a chave.
    const funil = seletores(wrapper)[1];
    expect(funil.props('options')[0]).toEqual({
      value: '',
      label: 'AUTOMACAO_LIVRE.GATILHO_DO_CARD.TODOS_OS_FUNIS',
    });
    await escolher(funil, 3);
    await escolher(seletores(wrapper)[1], '');

    await wrapper.find('[data-salvar]').trigger('click');
    const valor = wrapper.emitted('salvar')[0][0].valor;
    expect(valor.tipo).toBe('card.ganho');
    expect(valor).not.toHaveProperty('funil_id');
    expect(valor).not.toHaveProperty('etapa_id');
  });

  it('a frase do gatilho diz a etapa e o funil escolhidos', () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
    const { nomes } = ESCOLHAS;
    expect(
      fraseDoGatilho(
        { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
        CATALOGO,
        t,
        nomes
      )
    ).toBe('AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA Orçamento');
    expect(
      fraseDoGatilho({ tipo: 'card.ganho', funil_id: 3 }, CATALOGO, t, nomes)
    ).toBe('AUTOMACAO_LIVRE.GATILHO_COM.CARD_GANHO Vendas');
    // Sem funil (vale qualquer um) ou sem o nome na tela: a frase do catálogo.
    expect(fraseDoGatilho({ tipo: 'card.ganho' }, CATALOGO, t, nomes)).toBe(
      'AUTOMACAO_LIVRE.GATILHOS.CARD_GANHO'
    );
    expect(
      fraseDoGatilho(
        { tipo: 'card.entrou_na_etapa', etapa_id: 99 },
        CATALOGO,
        t
      )
    ).toBe('AUTOMACAO_LIVRE.GATILHOS.CARD_ENTROU_NA_ETAPA');
  });

  // Etapas de funis diferentes costumam ter o mesmo nome ("Negociação"): com
  // mais de um funil na conta, a frase diz também o funil da etapa.
  it('com dois funis, a frase da etapa diz o funil; com um, fica curta', async () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
    CrmKanbanAPI.getPipelines.mockResolvedValueOnce({
      data: {
        payload: [
          { id: 3, name: 'Vendas' },
          { id: 4, name: 'Pós-venda' },
        ],
      },
    });
    CrmKanbanAPI.getStages
      .mockResolvedValueOnce({
        data: { payload: [{ id: 12, name: 'Negociação' }] },
      })
      .mockResolvedValueOnce({
        data: { payload: [{ id: 20, name: 'Negociação' }] },
      });
    const { escolhas, carregar } = useEscolhasDosGatilhos();
    await carregar();
    const { nomes } = escolhas.value;

    expect(nomes.funilDaEtapa).toEqual({ 12: 'Vendas', 20: 'Pós-venda' });
    expect(
      fraseDoGatilho(
        { tipo: 'card.entrou_na_etapa', etapa_id: 20 },
        CATALOGO,
        t,
        nomes
      )
    ).toBe(
      'AUTOMACAO_LIVRE.GATILHO_NO_FUNIL AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA Negociação Pós-venda'
    );
    // O funil do "card ganho" já está na frase: não repete.
    expect(
      fraseDoGatilho({ tipo: 'card.ganho', funil_id: 4 }, CATALOGO, t, nomes)
    ).toBe('AUTOMACAO_LIVRE.GATILHO_COM.CARD_GANHO Pós-venda');

    // Um funil só: sem o sufixo.
    const umFunil = useEscolhasDosGatilhos();
    await umFunil.carregar();
    expect(
      fraseDoGatilho(
        { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
        CATALOGO,
        t,
        umFunil.escolhas.value.nomes
      )
    ).toBe('AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA Orçamento');
  });
});
