import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useGatilhosNovos } from '../useGatilhosNovos';
import { fraseDoGatilho } from '../frases';
import AttributeAPI from 'dashboard/api/attributes';

// #2499 PR3a — os gatilhos de tempo no editor: o "parado na etapa" pede a etapa
// e os dias; os de data pedem o campo de data do próprio alvo (card ou
// contato), os dias, antes ou depois e a hora. Tudo vai como número, menos o
// campo (a chave) e o "quando". Cada um mostra o aviso dele.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => true) }),
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
const definicao = (modelo, chave, nome, tipo = 'date') => ({
  attribute_model: modelo,
  attribute_key: chave,
  attribute_display_name: nome,
  attribute_display_type: tipo,
});
const DEFINICOES = [
  definicao('card_attribute', 'vencimento', 'Vencimento'),
  definicao('card_attribute', 'placa', 'Placa', 'text'),
  definicao('contact_attribute', 'aniversario', 'Aniversário'),
  definicao('contact_attribute', 'cidade', 'Cidade', 'text'),
  definicao('conversation_attribute', 'retorno', 'Retorno'),
];
vi.mock('dashboard/api/attributes', () => ({
  default: { getAttributesByModel: vi.fn() },
}));

const parametro = (nome, peca) => ({
  nome,
  peca,
  obrigatorio: true,
  frase: `AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.${nome.toUpperCase()}`,
});
const DA_DATA = [
  ...['campo', 'dias', 'quando', 'hora'].map(nome => parametro(nome, nome)),
  { ...parametro('repete', 'repete'), obrigatorio: false },
];
const deTempo = (tipo, alvo, chave, parametros) => ({
  tipo,
  alvo,
  frase: `AUTOMACAO_LIVRE.GATILHOS.${chave}`,
  grupo: 'tempo',
  requer: 'automacao_gatilhos',
  ...(alvo === 'Crm::Card' ? { funil: true } : {}),
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
    {
      tipo: 'card.entrou_na_etapa',
      alvo: 'Crm::Card',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_ENTROU_NA_ETAPA',
      grupo: 'card',
      requer: 'automacao_gatilhos',
      funil: true,
      parametros: [parametro('etapa_id', 'etapa')],
    },
    deTempo('card.parado', 'Crm::Card', 'CARD_PARADO', [
      parametro('etapa_id', 'etapa'),
      parametro('dias', 'dias'),
    ]),
    deTempo('card.data', 'Crm::Card', 'CARD_DATA', DA_DATA),
    deTempo('contato.data', 'Contact', 'CONTATO_DATA', DA_DATA),
  ],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [],
};

// As escolhas como o editor as recebe: pelo próprio composable, com a flag.
const oferecidos = async (catalogo = CATALOGO) => {
  let resultado;
  mount({
    setup() {
      resultado = useGatilhosNovos(
        flag => flag === 'automacao_gatilhos',
        ref(catalogo)
      );
      return {};
    },
    template: '<div />',
  });
  await flushPromises();
  return resultado;
};

const PainelFalso = {
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
};
const montar = async () => {
  const { gatilhos, escolhasDoGatilho } = await oferecidos();
  const wrapper = mount(LivreAlterar, {
    props: {
      catalogo: CATALOGO,
      opcoes: {},
      atributosDaPeca: () => [],
      atributosDo: () => [],
      gatilhos: gatilhos.value,
      escolhasDoGatilho: escolhasDoGatilho.value,
    },
    global: {
      stubs: { SidePanel: PainelFalso },
      mocks: { $t: chave => chave },
    },
  });
  wrapper.vm.abrir({ tipo: 'gatilho', valor: null });
  await flushPromises();
  return wrapper;
};
const seletorDo = (wrapper, nome) =>
  wrapper
    .find(`[data-parametro="${nome}"]`)
    .findComponent({ name: 'ChoiceSelect' });
const escolher = async (seletor, valor) => {
  seletor.vm.$emit('update:modelValue', valor);
  await flushPromises();
};
const escolherTipo = (wrapper, tipo) =>
  escolher(wrapper.findAllComponents({ name: 'ChoiceSelect' })[0], tipo);
const digitarDias = async (wrapper, valor) => {
  wrapper
    .find('[data-parametro="dias"]')
    .findComponent(Input)
    .vm.$emit('update:modelValue', valor);
  await flushPromises();
};
const salvarDesligado = wrapper =>
  wrapper.find('[data-salvar]').attributes('disabled') !== undefined;
// O gatilho salvo, sem os filtros do "Só se" (que o painel sempre leva).
const salvo = async wrapper => {
  await wrapper.find('[data-salvar]').trigger('click');
  const { filtros: _filtros, ...gatilho } =
    wrapper.emitted('salvar')[0][0].valor;
  return gatilho;
};
const aviso = wrapper => wrapper.find('[data-aviso-tempo]');

describe('gatilhos de tempo', () => {
  beforeEach(() => {
    AttributeAPI.getAttributesByModel.mockReset();
    AttributeAPI.getAttributesByModel.mockResolvedValue({ data: DEFINICOES });
  });

  it('só lê os campos de data quando algum gatilho oferecido pede o campo', async () => {
    await oferecidos({
      ...CATALOGO,
      gatilhos: CATALOGO.gatilhos.filter(
        item => !['card.data', 'contato.data'].includes(item.tipo)
      ),
    });
    expect(AttributeAPI.getAttributesByModel).not.toHaveBeenCalled();

    const { escolhasDoGatilho } = await oferecidos();
    expect(AttributeAPI.getAttributesByModel).toHaveBeenCalledTimes(1);
    expect(escolhasDoGatilho.value.nomes.campo).toEqual({
      'Crm::Card': { vencimento: 'Vencimento' },
      Contact: { aniversario: 'Aniversário' },
    });
  });

  it('"parado na etapa" pede a etapa e os dias e grava os dois como número', async () => {
    const wrapper = await montar();
    await escolherTipo(wrapper, 'card.parado');

    expect(wrapper.find('[data-parametro="etapa_id"]').exists()).toBe(true);
    const dias = wrapper.find('[data-parametro="dias"]').findComponent(Input);
    // Já vem com 3 dias; o "parado" conta de 1 a 365.
    expect(dias.props('modelValue')).toBe('3');
    expect(dias.props('min')).toBe('1');
    expect(dias.props('max')).toBe('365');
    expect(salvarDesligado(wrapper)).toBe(true);

    await escolher(seletorDo(wrapper, 'etapa_id'), 12);
    await digitarDias(wrapper, 0);
    expect(dias.props('modelValue')).toBe('1');
    await digitarDias(wrapper, 900);
    expect(dias.props('modelValue')).toBe('365');
    // Apagado, o "Salvar" espera um número.
    await digitarDias(wrapper, '');
    expect(salvarDesligado(wrapper)).toBe(true);
    await digitarDias(wrapper, 7);
    expect(salvarDesligado(wrapper)).toBe(false);

    expect(wrapper.find('[data-frase-alterar]').text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_PARADO Orçamento 7'
    );
    expect(await salvo(wrapper)).toEqual({
      tipo: 'card.parado',
      etapa_id: 12,
      dias: 7,
    });
  });

  it('"data do card" grava o campo, os dias, o quando e a hora, e só oferece campos de data do card', async () => {
    const wrapper = await montar();
    await escolherTipo(wrapper, 'card.data');

    expect(seletorDo(wrapper, 'campo').props('options')).toEqual([
      { value: 'vencimento', label: 'Vencimento' },
    ]);
    expect(seletorDo(wrapper, 'quando').props('options')).toEqual([
      { value: 'antes', label: 'AUTOMACAO_LIVRE.QUANDO_DA_DATA.ANTES' },
      { value: 'depois', label: 'AUTOMACAO_LIVRE.QUANDO_DA_DATA.DEPOIS' },
    ]);
    const horas = seletorDo(wrapper, 'hora').props('options');
    expect(horas).toHaveLength(24);
    expect(horas[0]).toEqual({
      value: 0,
      label: 'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.HORA 0',
    });
    expect(horas[23].value).toBe(23);
    // O de data aceita 0 dias (o próprio dia).
    expect(
      wrapper.find('[data-parametro="dias"]').findComponent(Input).props('min')
    ).toBe('0');

    // Já vem 30 dias antes, a partir das 8h; falta o campo.
    expect(salvarDesligado(wrapper)).toBe(true);
    await escolher(seletorDo(wrapper, 'campo'), 'vencimento');
    expect(salvarDesligado(wrapper)).toBe(false);
    expect(wrapper.find('[data-frase-alterar]').text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_DATA Vencimento 30 AUTOMACAO_LIVRE.QUANDO_DA_DATA.ANTES 8'
    );

    await digitarDias(wrapper, 0);
    await escolher(seletorDo(wrapper, 'quando'), 'depois');
    await escolher(seletorDo(wrapper, 'hora'), 0);
    expect(salvarDesligado(wrapper)).toBe(false);
    expect(await salvo(wrapper)).toEqual({
      tipo: 'card.data',
      campo: 'vencimento',
      dias: 0,
      quando: 'depois',
      hora: 0,
    });
  });

  it('"repete" começa em uma vez, grava todo ano e volta a tirar a chave', async () => {
    const wrapper = await montar();
    await escolherTipo(wrapper, 'contato.data');
    await escolher(seletorDo(wrapper, 'campo'), 'aniversario');

    expect(seletorDo(wrapper, 'repete').props('modelValue')).toBe('uma_vez');
    expect(seletorDo(wrapper, 'repete').props('options')).toEqual([
      { value: 'uma_vez', label: 'AUTOMACAO_LIVRE.REPETE_DA_DATA.UMA_VEZ' },
      { value: 'todo_ano', label: 'AUTOMACAO_LIVRE.REPETE_DA_DATA.TODO_ANO' },
    ]);
    await escolher(seletorDo(wrapper, 'repete'), 'todo_ano');
    expect(await salvo(wrapper)).toMatchObject({ repete: 'todo_ano' });

    await escolher(seletorDo(wrapper, 'repete'), 'uma_vez');
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar').at(-1)[0].valor).not.toHaveProperty(
      'repete'
    );
  });

  it('"data do contato" só oferece campos de data do contato', async () => {
    const wrapper = await montar();
    await escolherTipo(wrapper, 'contato.data');
    expect(seletorDo(wrapper, 'campo').props('options')).toEqual([
      { value: 'aniversario', label: 'Aniversário' },
    ]);
    expect(wrapper.find('[data-sem-campo]').exists()).toBe(false);
  });

  it('sem campo de data no alvo, diz como criar um e não salva', async () => {
    AttributeAPI.getAttributesByModel.mockResolvedValue({
      data: [definicao('card_attribute', 'vencimento', 'Vencimento')],
    });
    const wrapper = await montar();
    await escolherTipo(wrapper, 'contato.data');

    const semCampo = wrapper.find('[data-sem-campo]');
    expect(semCampo.text()).toBe('AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.SEM_CAMPO');
    expect(seletorDo(wrapper, 'campo').exists()).toBe(false);
    expect(salvarDesligado(wrapper)).toBe(true);
  });

  it('cada gatilho mostra o aviso dele', async () => {
    const wrapper = await montar();

    await escolherTipo(wrapper, 'card.parado');
    expect(aviso(wrapper).text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_PARADO'
    );
    // O aviso de mover a etapa não vale para o "parado".
    expect(wrapper.find('[data-nao-dispara]').exists()).toBe(false);

    const avisaDaData = async tipo => {
      await escolherTipo(wrapper, tipo);
      expect(aviso(wrapper).text()).toBe(
        'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_DATA'
      );
      expect(wrapper.find('[data-nao-dispara]').exists()).toBe(false);
    };
    await avisaDaData('card.data');
    await avisaDaData('contato.data');

    await escolherTipo(wrapper, 'card.entrou_na_etapa');
    expect(aviso(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-nao-dispara]').exists()).toBe(true);

    await escolherTipo(wrapper, 'conversa.criada');
    expect(aviso(wrapper).exists()).toBe(false);
  });

  describe('a frase', () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
    const NOMES = {
      etapa: { 12: 'Orçamento' },
      funil: { 3: 'Vendas' },
      funilDaEtapa: {},
      campo: {
        'Crm::Card': { vencimento: 'Vencimento' },
        Contact: { aniversario: 'Aniversário' },
      },
    };
    const doContato = valores => ({
      tipo: 'contato.data',
      campo: 'aniversario',
      quando: 'antes',
      hora: 9,
      ...valores,
    });

    it('com dias, diz os dias, o quando, o campo e a hora', () => {
      expect(fraseDoGatilho(doContato({ dias: 5 }), CATALOGO, t, NOMES)).toBe(
        'AUTOMACAO_LIVRE.GATILHO_COM.CONTATO_DATA Aniversário 5 AUTOMACAO_LIVRE.QUANDO_DA_DATA.ANTES 9'
      );
    });

    it('todo ano diz isso no fim da frase', () => {
      expect(
        fraseDoGatilho(
          doContato({ dias: 0, repete: 'todo_ano' }),
          CATALOGO,
          t,
          NOMES
        )
      ).toBe(
        'AUTOMACAO_LIVRE.GATILHO_TODO_ANO AUTOMACAO_LIVRE.GATILHO_NO_DIA.CONTATO_DATA Aniversário 0 AUTOMACAO_LIVRE.QUANDO_DA_DATA.ANTES 9'
      );
    });

    it('com 0 dias, fala do próprio dia', () => {
      expect(fraseDoGatilho(doContato({ dias: 0 }), CATALOGO, t, NOMES)).toBe(
        'AUTOMACAO_LIVRE.GATILHO_NO_DIA.CONTATO_DATA Aniversário 0 AUTOMACAO_LIVRE.QUANDO_DA_DATA.ANTES 9'
      );
    });

    it('sem o nome do campo ou da etapa, fica a do catálogo', () => {
      expect(fraseDoGatilho(doContato({ dias: 5 }), CATALOGO, t)).toBe(
        'AUTOMACAO_LIVRE.GATILHOS.CONTATO_DATA'
      );
      // O campo do card não serve ao contato, mesmo com a mesma chave.
      expect(
        fraseDoGatilho(
          doContato({ dias: 5, campo: 'vencimento' }),
          CATALOGO,
          t,
          NOMES
        )
      ).toBe('AUTOMACAO_LIVRE.GATILHOS.CONTATO_DATA');
      expect(
        fraseDoGatilho(
          { tipo: 'card.parado', etapa_id: 99, dias: 3 },
          CATALOGO,
          t,
          NOMES
        )
      ).toBe('AUTOMACAO_LIVRE.GATILHOS.CARD_PARADO');
    });

    it('o "parado" com mais de um funil diz o funil da etapa', () => {
      expect(
        fraseDoGatilho(
          { tipo: 'card.parado', etapa_id: 12, dias: 3 },
          CATALOGO,
          t,
          { ...NOMES, funilDaEtapa: { 12: 'Vendas' } }
        )
      ).toBe(
        'AUTOMACAO_LIVRE.GATILHO_NO_FUNIL AUTOMACAO_LIVRE.GATILHO_COM.CARD_PARADO Orçamento 3 Vendas'
      );
    });
  });
});
