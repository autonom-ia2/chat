import { flushPromises, mount } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreEnsaio from '../components/LivreEnsaio.vue';
import { linhasDoEnsaio } from '../ensaio';

// #2498 — Ensaiar: a salva sem mudança ensaia a versão dela (sem receita no
// corpo); rascunho e nova mandam a receita. O "se" diz o que vale hoje, o
// "esperar até" mostra os dois caminhos e a mensagem sem a flag avisa que não
// sairia. Receita com problema mostra as frases da API.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { ensaiar: vi.fn() },
}));

const CATALOGO = {
  gatilhos: [],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [
    { tipo: 'parar', grupo: 'CONTROLE', frase: 'PARAR', campos: [] },
    { tipo: 'mensagem', grupo: 'FALAR', frase: 'MENSAGEM', campos: [] },
  ],
};

const RECEITA = {
  gatilho: { tipo: 'conversa.resolvida' },
  passos: [
    { id: 'm1', tipo: 'mensagem', texto: ['Oi'] },
    { id: 'p1', tipo: 'parar' },
  ],
};

const conversa = (id, extra = {}) => ({
  conversa_id: id,
  nome: `Contato ${id}`,
  ultima_atividade: '2026-11-04T10:00:00Z',
  entraria: true,
  motivo: null,
  passos: [
    { id: 'm1', tipo: 'mensagem', faria: 'mensagem', dados: { texto: 'Oi' } },
    { id: 'p1', tipo: 'parar', faria: 'parar', dados: {} },
  ],
  ...extra,
});

const montar = (props = {}) =>
  mount(LivreEnsaio, {
    props: { automacaoId: 5, receita: RECEITA, catalogo: CATALOGO, ...props },
    global: { mocks: { $t: t } },
  });

describe('LivreEnsaio', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Element.prototype.scrollIntoView = vi.fn();
    window.matchMedia = vi.fn(() => ({ matches: false }));
  });

  it('a salva sem mudança ensaia a versão dela, sem mandar a receita', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: { conversas: [conversa(1)], outras: [] },
    });
    const wrapper = montar();
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).toHaveBeenCalledWith(5, {
      receita: undefined,
      conversaId: undefined,
    });
    expect(wrapper.find('[data-casaram]').text()).toBe('1');
    expect(wrapper.find('[data-balao]').text()).toBe('Oi');
  });

  it('com rascunho, e na nova, manda a receita da tela', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValue({
      data: { conversas: [], outras: [] },
    });
    montar({ rascunho: true });
    montar({ automacaoId: null });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar.mock.calls).toEqual([
      [5, { receita: RECEITA, conversaId: undefined }],
      [null, { receita: RECEITA, conversaId: undefined }],
    ]);
  });

  it('a conversa que não entraria diz por quê', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: {
        conversas: [conversa(1, { entraria: false, motivo: 'spam' })],
        outras: [],
      },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-nao-entra]').text()).toBe(
      'AUTOMACAO_LIVRE.ENSAIO.FORA.SPAM'
    );
  });

  it('receita com problema mostra as frases da API', async () => {
    AutomacoesAPI.ensaiar.mockRejectedValueOnce({
      response: { data: { error: 'Corrija', problemas: ['Passo m1: x'] } },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-erro]').text()).toContain('Corrija');
    expect(wrapper.find('[data-erro] li').text()).toBe('Passo m1: x');
  });

  it('fechar avisa o editor', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: { conversas: [], outras: [] },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-fechar-ensaio]').trigger('click');

    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });
});

describe('linhasDoEnsaio', () => {
  const fraseDe = id => `frase ${id}`;

  it('o "se" diz o que vale hoje', () => {
    const [linha] = linhasDoEnsaio(
      [{ id: 's1', tipo: 'se', faria: 'se', dados: { ramo: 'senao' } }],
      fraseDe,
      t
    );

    expect(linha).toMatchObject({
      texto: 'frase s1',
      destaque: 'AUTOMACAO_LIVRE.ENSAIO.HOJE_NAO',
    });
  });

  it('o "esperar até" abre os dois caminhos, cada um um nível adentro', () => {
    const linhas = linhasDoEnsaio(
      [
        {
          id: 'a1',
          tipo: 'esperar_ate',
          faria: 'esperar_ate',
          dados: {},
          ramos: [
            {
              chave: 'chegou',
              passos: [{ id: 'r1', tipo: 'parar', faria: 'parar' }],
            },
            {
              chave: 'se_vencer',
              passos: [{ id: 'v1', tipo: 'parar', faria: 'parar' }],
            },
          ],
        },
      ],
      fraseDe,
      t
    );

    expect(linhas.map(linha => [linha.nivel, linha.texto])).toEqual([
      [0, 'frase a1'],
      [1, 'AUTOMACAO_LIVRE.ENSAIO.SE_CHEGAR'],
      [2, 'frase r1'],
      [1, 'AUTOMACAO_LIVRE.ENSAIO.SE_VENCER'],
      [2, 'frase v1'],
    ]);
  });

  it('sem a mensagem automática, avisa que não sairia', () => {
    const [linha] = linhasDoEnsaio(
      [{ id: 'm1', tipo: 'mensagem', faria: 'mensagens_desligadas' }],
      fraseDe,
      t
    );

    expect(linha.aviso).toBe('AUTOMACAO_LIVRE.ENSAIO.NAO_SAIRIA');
    expect(linha.balao).toBeUndefined();
  });

  // #2523: o aviso só para o responsável, na conversa sem responsável.
  it('o aviso sem responsável diz que ninguém seria avisado', () => {
    const [linha] = linhasDoEnsaio(
      [{ id: 'a1', tipo: 'avisar', faria: 'sem_responsavel' }],
      fraseDe,
      t
    );

    expect(linha.aviso).toBe('AUTOMACAO_LIVRE.ENSAIO.SEM_RESPONSAVEL');
    expect(linha.balao).toBeUndefined();
  });

  // #2552: sem responsável, com a reserva, o aviso iria para a caixa.
  it('o aviso com a reserva mostra o texto e diz que iria para a caixa', () => {
    const [linha] = linhasDoEnsaio(
      [
        {
          id: 'a1',
          tipo: 'avisar',
          faria: 'avisar',
          dados: { texto: 'Chegou reclamação', reserva: 'caixa' },
        },
      ],
      fraseDe,
      t
    );

    expect(linha.balao).toBe('Chegou reclamação');
    expect(linha.destaque).toBe('AUTOMACAO_LIVRE.ENSAIO.IRIA_PARA_CAIXA');
  });

  it('o "decidir" rotula cada caminho e o "nenhum"', () => {
    const linhas = linhasDoEnsaio(
      [
        {
          id: 'd1',
          tipo: 'decidir',
          faria: 'decidir',
          ramos: [
            { chave: 'cotacao', nome: 'Cotação', passos: [] },
            { chave: 'nenhum', passos: [] },
          ],
        },
      ],
      fraseDe,
      t
    );

    expect(linhas.filter(linha => linha.caminho).map(l => l.texto)).toEqual([
      'AUTOMACAO_LIVRE.ENSAIO.SE_CAMINHO(Cotação)',
      'AUTOMACAO_LIVRE.ENSAIO.SE_NENHUM',
    ]);
  });

  // #2500 — extrair, escrever e resumir dizem para onde iria o que a IA
  // fizesse; nada vem da IA. Lugar que o painel não conhece mostra só o campo.
  it.each([
    [
      'extrair',
      {
        campos: [
          { chave: 'placa', destino: 'conversa.placa' },
          { chave: 'cpf', destino: 'contato.cpf' },
          { chave: 'empresa', destino: 'empresa.nome' },
          { chave: 'etapa', destino: 'card.atributos.etapa' },
          { chave: 'sem_destino', destino: '' },
        ],
      },
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_EXTRAIR(AUTOMACAO_LIVRE.ENSAIO.FARIA.ONDE.CONVERSA(placa); AUTOMACAO_LIVRE.ENSAIO.FARIA.ONDE.CONTATO(cpf); AUTOMACAO_LIVRE.ENSAIO.FARIA.ONDE.EMPRESA(empresa); etapa; sem_destino)',
    ],
    [
      'escrever',
      { destino: 'mensagem' },
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_ESCREVER_MENSAGEM',
    ],
    [
      'escrever',
      { destino: 'sugestao' },
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_ESCREVER_SUGESTAO',
    ],
    [
      'resumir',
      { destino: 'nota' },
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_RESUMIR_NOTA',
    ],
    [
      'resumir',
      { destino: 'avisar' },
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_RESUMIR_AVISAR',
    ],
  ])('o "%s" diz o que a IA faria', (tipo, dados, destaque) => {
    const [linha] = linhasDoEnsaio(
      [{ id: 'i1', tipo, faria: `ia_${tipo}`, dados }],
      fraseDe,
      t
    );

    expect(linha).toMatchObject({ texto: 'frase i1', destaque });
  });

  // #2552: o resumo que sai pelo avisar, com a reserva, diz que iria para a caixa.
  it('o resumo com a reserva diz que avisaria e que iria para a caixa', () => {
    const [linha] = linhasDoEnsaio(
      [
        {
          id: 'i1',
          tipo: 'resumir',
          faria: 'ia_resumir',
          dados: { destino: 'avisar', reserva: 'caixa' },
        },
      ],
      fraseDe,
      t
    );

    expect(linha.destaque).toBe(
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_RESUMIR_AVISAR AUTOMACAO_LIVRE.ENSAIO.IRIA_PARA_CAIXA'
    );
    expect(linha.balao).toBeUndefined();
  });
});
