import { flushPromises, mount } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreHistorico from '../components/LivreHistorico.vue';

// #2498 — "O que aconteceu": a frase de cada passo sai da receita da versão em
// que a execução entrou; pulo e falha levam o motivo; conversa que a pessoa não
// vê aparece sem nome e sem link; "Ver mais" busca a página seguinte.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { historico: vi.fn() },
}));

const CATALOGO = {
  gatilhos: [],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [
    { tipo: 'parar', grupo: 'CONTROLE', frase: 'PARAR', campos: [] },
    { tipo: 'se', grupo: 'CONTROLE', frase: 'SE', campos: [] },
  ],
};

const VERSOES = {
  21: {
    numero: 1,
    receita: {
      gatilho: { tipo: 'conversa.criada' },
      passos: [{ id: 'p1', tipo: 'parar' }],
    },
  },
};

const execucao = (id, extra = {}) => ({
  id,
  estado: 'concluida',
  versao_id: 21,
  criada_em: '2026-11-03T10:00:00Z',
  alvo: { tipo: 'conversa', visivel: true, conversa_id: 40, nome: 'Maria' },
  passos: [
    { passo: 'p1', resultado: 'ok', motivo: null, dados: { mensagem_id: 9 } },
  ],
  ...extra,
});

const responder = (
  execucoes,
  { mais = false, pagina = 1, versoes = VERSOES } = {}
) =>
  AutomacoesAPI.historico.mockResolvedValueOnce({
    data: { execucoes, versoes, pagina, mais },
  });

const montar = () =>
  mount(LivreHistorico, {
    props: { automacaoId: 5, catalogo: CATALOGO, accountId: 1 },
    global: {
      mocks: {
        $t: (chave, valores) =>
          valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
      },
    },
  });

describe('LivreHistorico', () => {
  beforeEach(() => vi.clearAllMocks());

  it('mostra a execução aberta com a frase do passo e o link da conversa', async () => {
    responder([execucao(1)]);
    const wrapper = montar();
    await flushPromises();

    expect(AutomacoesAPI.historico).toHaveBeenCalledWith(5, 1);
    expect(wrapper.find('[data-execucao]').text()).toContain(
      'AUTOMACAO_LIVRE.HISTORICO.CONVERSA_DE(Maria)'
    );
    expect(wrapper.find('[data-passo]').text()).toContain('PARAR');
    expect(wrapper.find('[data-abrir-conversa]').attributes('href')).toBe(
      '/app/accounts/1/conversations/40'
    );
    expect(wrapper.find('[data-ver-mensagem]').attributes('href')).toBe(
      '/app/accounts/1/conversations/40?messageId=9'
    );
  });

  it('pulo e falha levam o prefixo e o motivo traduzido', async () => {
    responder([
      execucao(1, {
        estado: 'parada',
        passos: [
          {
            passo: 'p1',
            resultado: 'pulado',
            motivo: 'A conversa está no Spam.',
            dados: {},
          },
        ],
      }),
    ]);
    const wrapper = montar();
    await flushPromises();

    const passo = wrapper.find('[data-passo]');
    expect(passo.text()).toContain('AUTOMACAO_LIVRE.HISTORICO.PULOU(PARAR)');
    expect(passo.find('[data-motivo]').text()).toBe('A conversa está no Spam.');
    expect(wrapper.find('[data-estado]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.ESTADOS.PARADA'
    );
  });

  // G42: o resumo diz quantas conversas deixou de fora, sem os ids.
  it('o resumo diz quantas conversas deixou de fora', async () => {
    responder([
      execucao(1, {
        passos: [
          {
            passo: 'p1',
            resultado: 'ok',
            motivo: null,
            dados: { conversas_fora: 2 },
          },
        ],
      }),
    ]);
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-conversas-fora]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.CONVERSAS_FORA(2)'
    );
  });

  it('o "se" diz por qual caminho seguiu', async () => {
    responder([
      execucao(1, {
        passos: [
          {
            passo: 'p1',
            resultado: 'ok',
            motivo: null,
            dados: { ramo: 'senao' },
          },
        ],
      }),
    ]);
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-ramo]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR(AUTOMACAO_LIVRE.RAMOS.SENAO)'
    );
  });

  it('conversa que a pessoa não vê fica sem nome e sem link', async () => {
    responder([
      execucao(1, {
        alvo: { tipo: 'conversa', visivel: false },
        passos: [{ passo: 'p1', resultado: 'ok', motivo: null, dados: {} }],
      }),
    ]);
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-oculta]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.OCULTA'
    );
    expect(wrapper.find('[data-abrir-conversa]').exists()).toBe(false);
    expect(wrapper.find('[data-ver-mensagem]').exists()).toBe(false);
  });

  // #2500 — o custo do passo fica na casa de US$ 0,0001: dois algarismos
  // significativos, e abaixo do mínimo "menos de", nunca "US$ 0".
  it.each([
    [0, 'AUTOMACAO_LIVRE.HISTORICO.IA_MENOS_DE(0,0001)'],
    [0.00004, 'AUTOMACAO_LIVRE.HISTORICO.IA_MENOS_DE(0,0001)'],
    [0.000135, 'AUTOMACAO_LIVRE.HISTORICO.IA(0,00014)'],
    [0.0021, 'AUTOMACAO_LIVRE.HISTORICO.IA(0,0021)'],
    [1.5, 'AUTOMACAO_LIVRE.HISTORICO.IA(1,5)'],
  ])('o custo de IA %s aparece como %s', async (custo, texto) => {
    responder([
      execucao(1, {
        passos: [
          {
            passo: 'p1',
            resultado: 'ok',
            motivo: null,
            dados: { ia: { custo_usd: custo } },
          },
        ],
      }),
    ]);
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-ia]').text()).toBe(texto);
  });

  // #2500 — o caminho do "decidir" aparece pelo nome que tinha na versão que
  // rodou, mesmo que a pessoa tenha renomeado depois; nunca pela chave.
  it('o decidir mostra o nome do caminho na versão que rodou', async () => {
    const decidir = nome => ({
      numero: 1,
      receita: {
        gatilho: { tipo: 'conversa.criada' },
        passos: [
          {
            id: 'p1',
            tipo: 'decidir',
            pergunta: 'O que o cliente quer?',
            caminhos: [
              { chave: 'sinistro', nome, passos: [] },
              { chave: 'cotacao', nome: 'Cotação', passos: [] },
            ],
          },
        ],
      },
    });
    const passos = ramo => [
      { passo: 'p1', resultado: 'ok', motivo: null, dados: { ramo } },
    ];
    responder(
      [
        execucao(1, { versao_id: 21, passos: passos('sinistro') }),
        execucao(2, { versao_id: 22, passos: passos('sinistro') }),
        execucao(3, { versao_id: 22, passos: passos('nenhum') }),
      ],
      { versoes: { 21: decidir('Sinistro'), 22: decidir('Batida de carro') } }
    );
    const wrapper = montar();
    await flushPromises();
    // A primeira já vem aberta; abrir outra fecha a anterior.
    const linhas = wrapper.findAll('[data-execucao]');
    const ramo = () => wrapper.find('[data-ramo]').text();
    const ramos = [ramo()];
    await linhas[1].trigger('click');
    ramos.push(ramo());
    await linhas[2].trigger('click');
    ramos.push(ramo());

    expect(ramos).toEqual([
      'AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR(Sinistro)',
      'AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR(Batida de carro)',
      'AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR(AUTOMACAO_LIVRE.RAMOS.NENHUM)',
    ]);
  });

  it('"Ver mais" traz a página seguinte embaixo', async () => {
    responder([execucao(1)], { mais: true });
    const wrapper = montar();
    await flushPromises();

    responder([execucao(2)], { pagina: 2 });
    await wrapper.find('[data-ver-mais]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.historico).toHaveBeenLastCalledWith(5, 2);
    expect(wrapper.findAll('[data-execucao]')).toHaveLength(2);
    expect(wrapper.find('[data-ver-mais]').exists()).toBe(false);
  });

  it('sem execução, diz que ainda não rodou; erro oferece tentar de novo', async () => {
    responder([]);
    const vazio = montar();
    await flushPromises();
    expect(vazio.find('[data-vazio]').exists()).toBe(true);

    AutomacoesAPI.historico.mockRejectedValueOnce(new Error('rede'));
    const falhou = montar();
    await flushPromises();
    expect(falhou.find('[data-erro]').exists()).toBe(true);
  });
});
