import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CrmNumerosAPI from 'dashboard/api/crmNumeros';
import CrmNumerosEquipe from './CrmNumerosEquipe.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
import en from 'dashboard/i18n/locale/en/crm.json';

// A visão "Equipe" (#1992, F5 do #1871) na ordem do protótipo: topo, próximo
// passo, Vendendo, Atendendo, "Quem precisa de ajuda" e "Quem cuidou"
// recolhido, com a IA numa linha só. O custo só aparece quando o servidor manda
// (só para o dono), e o modo leitura avisa.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) =>
      params ? `${chave} ${JSON.stringify(params)}` : chave,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {}, params: { accountId: 1 } }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('pt-BR') }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({}) }),
}));
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir: () => true }),
}));
vi.mock('dashboard/api/crmNumeros', () => ({ default: { show: vi.fn() } }));

const MES = {
  chave: '2026-10',
  dia: 19,
  diasNoMes: 31,
  diasRestantes: 12,
  fechado: false,
  anterior: '2026-09',
  seguinte: null,
};

const ia = (extra = {}) => ({
  nome: 'Sofia',
  agenteId: 5,
  atendeu: 180,
  venda: { atendeu: 110, passou: 30, participou: 7, valor: 5400 },
  atende: { resolveuSozinha: 40, passou: 25 },
  custo: null,
  ...extra,
});

const dados = (extra = {}) => ({
  vazio: false,
  papel: 'dono',
  mes: MES,
  moeda: 'BRL',
  estimado: false,
  leitura: false,
  funis: { vendas: 1, suporte: 2 },
  topo: {
    escopo: 'empresa',
    medida: 'valor',
    feito: 13200,
    meta: 20000,
    fechadas: 18,
    esperadoPct: 61,
    frase: { tipo: 'empresa', feito: 13200, meta: 20000, resolvidos: 95 },
    botao: { tipo: 'parados', n: 9, valor: 11400 },
  },
  proximo: [
    { tipo: 'sem_responsavel', n: 3, aviso: true },
    { tipo: 'ia_esperando', n: 5, ia: null, aviso: true },
  ],
  vendendo: {
    escopo: 'equipe',
    itens: [
      { tipo: 'fechadas', n: 18, valor: 13200, lista: true },
      { tipo: 'andamento', n: 64 },
      { tipo: 'atrasados', n: 11 },
    ],
  },
  atendendo: {
    escopo: 'equipe',
    itens: [
      { tipo: 'resolvidos', n: 95, lista: true },
      { tipo: 'lembretes', n: 7 },
      { tipo: 'parados_atende', n: 5 },
    ],
  },
  ajuda: [
    {
      tipo: 'retornos',
      pessoa: { id: 12, nome: 'Bruno' },
      recebeu: 30,
      fechou: 4,
      n: 8,
    },
  ],
  quemCuidou: {
    pessoas: 2,
    linhas: [
      {
        id: 11,
        nome: 'Ana',
        voce: false,
        venda: { recebeu: 35, fechou: 9, valor: 6200, meta: null, pct: null },
      },
      {
        id: 13,
        nome: 'Carla',
        voce: true,
        atende: { resolveu: 70, noPrazo: null, meta: null, pct: null },
      },
    ],
    caminhoCerto: [],
    reconhecimento: null,
    plataforma: { ia: 'Sofia', atendeu: 180, participou: 7, valor: 5400 },
    ia: ia(),
  },
  visoes: ['eu', 'equipe'],
  visao: 'equipe',
  ...extra,
});

const montar = async resposta => {
  CrmNumerosAPI.show.mockResolvedValue({ data: resposta });
  const wrapper = mount(CrmNumerosEquipe, {
    props: { visoes: ['eu', 'equipe'] },
    global: {
      stubs: {
        CrmVistasNumeros: true,
        NumerosComoContamos: true,
        ResultsToggle: true,
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Banner: {
          props: ['color'],
          template: '<div data-banner :data-cor="color"><slot /></div>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CrmNumerosEquipe', () => {
  beforeEach(() => vi.clearAllMocks());

  it('pede a visão da equipe e mostra as seções na ordem do protótipo', async () => {
    const wrapper = await montar(dados());

    expect(CrmNumerosAPI.show).toHaveBeenCalledWith({
      mes: undefined,
      visao: 'equipe',
    });
    const ordem = [
      '[data-numeros-topo]',
      '[data-numeros-proximo]',
      '[data-numeros-bloco="vendendo"]',
      '[data-numeros-bloco="atendendo"]',
      '[data-numeros-ajuda]',
      '[data-numeros-cuidou]',
    ].map(seletor => {
      const el = wrapper.find(seletor);
      expect(el.exists(), seletor).toBe(true);
      return el.element;
    });
    ordem.slice(1).forEach((el, i) => {
      // eslint-disable-next-line no-bitwise
      const depois = ordem[i].compareDocumentPosition(el) & 4;
      expect(depois).toBe(4);
    });
  });

  it('no máximo uma faixa amarela, e "A IA" quando não há um nome só', async () => {
    const wrapper = await montar(dados());

    const faixas = wrapper.findAll('[data-proximo]');
    expect(faixas).toHaveLength(2);
    expect(
      faixas.filter(f => f.attributes('data-cor') === 'amber')
    ).toHaveLength(1);
    expect(wrapper.find('[data-proximo="ia_esperando"]').text()).toContain(
      '"ia":"CRM_NUMEROS_V2.IA_AJUDOU.IA"'
    );
  });

  it('a IA numa linha própria, sem meta e sem custo para quem não é o dono', async () => {
    const wrapper = await montar(dados());

    const linha = wrapper.find('[data-linha-ia]');
    expect(linha.exists()).toBe(true);
    expect(linha.text()).toContain('Sofia');
    expect(linha.find('[data-custo-ia]').exists()).toBe(false);
    expect(wrapper.findAll('[data-pessoa]')).toHaveLength(2);
  });

  it('o dono vê o custo da IA na moeda que o servidor manda', async () => {
    const resposta = dados();
    resposta.quemCuidou.ia = ia({
      custo: { valor: 52, porConversa: 0.29, moeda: 'BRL' },
    });
    const wrapper = await montar(resposta);

    const custo = wrapper.find('[data-custo-ia]').text();
    expect(custo).toContain('R$');
    expect(custo).toContain('CUIDOU.IA_CUSTO_AGENTES ');
  });

  it('o rótulo do custo diz "custo dos agentes de IA" (en e pt_BR)', () => {
    const cuidou = idioma => idioma.CRM_NUMEROS_V2.CUIDOU;
    const comeca = (idioma, inicio) =>
      ['IA_CUSTO_AGENTES', 'IA_CUSTO_AGENTES_SEM_CONVERSA'].every(chave =>
        cuidou(idioma)[chave].startsWith(inicio)
      );
    expect(comeca(ptBR, 'Custo dos agentes de IA:')).toBe(true);
    expect(comeca(en, 'AI agents cost:')).toBe(true);
  });

  it('modo leitura: avisa e não mostra o próximo passo', async () => {
    const wrapper = await montar(
      dados({
        leitura: true,
        papel: 'leitura',
        proximo: [],
        topo: { ...dados().topo, botao: null },
      })
    );

    expect(wrapper.find('[data-numeros-leitura]').exists()).toBe(true);
    expect(wrapper.find('[data-numeros-proximo]').exists()).toBe(false);
    expect(wrapper.find('[data-topo-botao]').exists()).toBe(false);
  });

  it('sem a IA no mês, "Quem cuidou" fala só das pessoas', async () => {
    const resposta = dados();
    resposta.quemCuidou = {
      ...resposta.quemCuidou,
      ia: null,
      plataforma: null,
    };
    const wrapper = await montar(resposta);

    expect(wrapper.find('[data-linha-ia]').exists()).toBe(false);
    expect(wrapper.find('[data-recolhido]').text()).toContain(
      'CUIDOU.TITULO_SEM_IA'
    );
  });
});
