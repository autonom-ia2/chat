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
// #2001 (F6): o atalho para "De onde vieram os clientes" segue a flag da conta.
const origensLigada = ref(false);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'accounts/isFeatureEnabledonAccount'
      ? ref((_conta, flag) =>
          flag === 'crm_numeros_origens' ? origensLigada.value : false
        )
      : ref(1),
}));

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
  passou: 55,
  venda: { participou: 7, valor: 5400 },
  atende: { resolveuSozinha: 40 },
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
      pessoa: { id: 12, nome: 'Bruno' },
      retornos: 8,
      casosParados: 5,
      total: 13,
    },
    {
      pessoa: { id: 13, nome: 'Carla' },
      retornos: 0,
      casosParados: 6,
      total: 6,
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
      {
        id: 12,
        nome: 'Bruno',
        voce: false,
        venda: { recebeu: 10, fechou: 2, valor: 1800, meta: null, pct: null },
        atende: { resolveu: 3, noPrazo: null, meta: null, pct: null },
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
        NumerosOrigensAtalho: {
          props: ['mesChave'],
          template: '<a data-origens-atalho-stub :data-mes="mesChave" />',
        },
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
  beforeEach(() => {
    vi.clearAllMocks();
    origensLigada.value = false;
  });

  it('mostra o atalho de "De onde vieram os clientes" só com a flag crm_numeros_origens', async () => {
    expect(
      (await montar(dados())).find('[data-origens-atalho-stub]').exists()
    ).toBe(false);

    origensLigada.value = true;
    const wrapper = await montar(dados());

    expect(
      wrapper.find('[data-origens-atalho-stub]').attributes('data-mes')
    ).toBe('2026-10');
  });

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

  it('a IA numa linha própria, sem meta e sem custo para quem não vê os custos da conta', async () => {
    const wrapper = await montar(dados());

    const linha = wrapper.find('[data-linha-ia]');
    expect(linha.exists()).toBe(true);
    expect(linha.text()).toContain('Sofia');
    expect(linha.find('[data-custo-ia]').exists()).toBe(false);
    expect(wrapper.findAll('[data-pessoa]')).toHaveLength(3);
  });

  it('quem vê os custos da conta vê o custo da IA na moeda que o servidor manda', async () => {
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

  // #1999: a mesma pessoa não ocupa duas vagas; cada número abre a sua fila.
  it('"precisa de ajuda": uma linha por pessoa, com retornos e casos parados lado a lado', async () => {
    const wrapper = await montar(dados());

    const linhas = wrapper.findAll('[data-ajuda-pessoa]');
    expect(linhas.map(linha => linha.attributes('data-ajuda-pessoa'))).toEqual([
      '12',
      '13',
    ]);
    const bruno = linhas[0];
    expect(bruno.text()).toContain('Bruno');
    expect(bruno.text()).toContain('AJUDA.RETORNOS_N {"n":8}');
    expect(bruno.text()).toContain('AJUDA.CASOS_PARADOS_N {"n":5}');
    expect(bruno.find('[data-ajuda="retornos"]').element.tagName).toBe('A');
    expect(bruno.find('[data-ajuda="casos_parados"]').element.tagName).toBe(
      'A'
    );
    expect(linhas[1].find('[data-ajuda="retornos"]').exists()).toBe(false);
  });

  // #1999: quem vende e atende tem uma linha só, com os dois números.
  it('"Quem cuidou": uma linha por pessoa, com venda e atendimento lado a lado', async () => {
    const wrapper = await montar(dados());

    const bruno = wrapper.findAll('[data-pessoa="pessoa-12"]');
    expect(bruno).toHaveLength(1);
    expect(bruno[0].text()).toContain('CUIDOU.VENDA');
    expect(bruno[0].text()).toContain('CUIDOU.ATENDE_SEM_PRAZO');
  });

  // #1999: sem meta de casos, abrir a linha não repete o "resolveu".
  it('abrir a linha de quem atende não repete o número de resolvidos', async () => {
    const wrapper = await montar(dados());

    await wrapper.find('[data-pessoa="pessoa-13"]').trigger('click');

    expect(wrapper.find('[data-numeros-cuidou]').text()).not.toContain(
      'DETALHE_ATENDE'
    );
  });

  // #1999: um número de cada para a IA, e a linha não repete a frase do topo.
  it('a linha da IA tem um "passou" só e não repete o que a frase do topo já diz', async () => {
    const wrapper = await montar(dados());

    const numeros = wrapper.find('[data-ia-numeros]').text();
    expect(numeros.split('CUIDOU.IA_PASSOU')).toHaveLength(2);
    expect(numeros).toContain('CUIDOU.IA_PASSOU {"n":55}');
    expect(numeros).toContain('CUIDOU.IA_RESOLVEU_SOZINHA {"n":40}');
    expect(numeros).not.toContain('IA_ATENDEU');
    expect(numeros).not.toContain('IA_PARTICIPOU');
  });

  // #2000: a página do agente mostra a mesma conta por semana; a linha avisa, ao lado do link.
  it('a linha da IA avisa que a página do agente mostra a mesma conta por semana', async () => {
    const wrapper = await montar(dados());

    expect(wrapper.find('[data-ia-semana]').text()).toContain(
      'CUIDOU.IA_SEMANA'
    );
  });

  it('sem a frase do topo, a linha da IA diz também quantos atendeu', async () => {
    const resposta = dados();
    resposta.quemCuidou.plataforma = null;
    const wrapper = await montar(resposta);

    const numeros = wrapper.find('[data-ia-numeros]').text();
    expect(numeros).toContain('CUIDOU.IA_ATENDEU {"n":180}');
    expect(numeros).toContain('CUIDOU.IA_PARTICIPOU');
  });

  // #1999: a última linha fecha a conta com o que fechou sem responsável ou com quem saiu.
  it('"Quem cuidou" fecha a conta com a linha de sem responsável ou fora da equipe', async () => {
    const resposta = dados();
    resposta.quemCuidou.foraDaEquipe = {
      venda: { fechou: 2, valor: 800 },
      atende: { resolveu: 1 },
    };
    const wrapper = await montar(resposta);

    const fora = wrapper.find('[data-fora-da-equipe]');
    expect(fora.text()).toContain('CUIDOU.FORA_DA_EQUIPE');
    expect(fora.text()).toContain('CUIDOU.FORA_VENDA');
    expect(fora.text()).toContain('CUIDOU.ATENDE_SEM_PRAZO');
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
