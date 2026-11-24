import { flushPromises, mount } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { useAlert } from 'dashboard/composables';
import LivreDuasVersoesResultado from '../components/LivreDuasVersoesResultado.vue';

// #3099 — no Histórico, o resultado de cada passo com duas versões: os números
// do servidor, o texto de cada versão da receita e o "Ficar com esta".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { duasVersoes: vi.fn(), escolherVersao: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const CATALOGO = {
  valores: [{ caminho: 'contato.nome', rotulo: 'Nome do contato' }],
  passos: [{ tipo: 'mensagem', frase: 'MENSAGEM', campos: [] }],
};
const regra = { criterio: 'respostas', divisao: 50, espera: 4 };
const passo = (id, texto2) => ({
  id,
  tipo: 'mensagem',
  texto: ['Oi, ', { $valor: 'contato.nome' }],
  versoes: { ...regra, texto: [texto2], modelo: null },
});
const RECEITA = {
  gatilho: { tipo: 'conversa.criada' },
  passos: [passo('p1', 'Olá!')],
};
const resultado = (id, extra = {}) => ({
  passo: id,
  estado: 'testando',
  criterio: 'respostas',
  espera: 4,
  faltam: 37,
  vencedora: null,
  versoes: [
    { numero: 1, receberam: 100, responderam: 10, compraram: 0, valor: null },
    { numero: 2, receberam: 63, responderam: 12, compraram: 0, valor: null },
  ],
  ...extra,
});

const Cartao = {
  name: 'ResultDuasVersoes',
  props: {
    teste: { type: Object, default: null },
    naAutomacao: Boolean,
    podeEscolher: Boolean,
    carregando: Boolean,
    enviando: { type: Number, default: null },
  },
  emits: ['escolher', 'recarregar'],
  template: '<div data-cartao />',
};

const montar = (receita = RECEITA) =>
  mount(LivreDuasVersoesResultado, {
    props: { automacaoId: 9, receita, catalogo: CATALOGO, podeEscolher: true },
    global: { stubs: { ResultDuasVersoes: Cartao } },
  });

describe('LivreDuasVersoesResultado', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('sem passo com duas versões, não pede nada ao servidor', async () => {
    const wrapper = montar({
      gatilho: null,
      passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Oi'] }],
    });
    await flushPromises();
    expect(AutomacoesAPI.duasVersoes).not.toHaveBeenCalled();
    expect(wrapper.findComponent(Cartao).exists()).toBe(false);
  });

  it('junta os números do servidor com o texto de cada versão', async () => {
    AutomacoesAPI.duasVersoes.mockResolvedValue({
      data: { passos: [resultado('p1')] },
    });
    const wrapper = montar();
    await flushPromises();

    expect(AutomacoesAPI.duasVersoes).toHaveBeenCalledWith(9);
    const cartao = wrapper.findComponent(Cartao);
    expect(cartao.props('naAutomacao')).toBe(true);
    expect(cartao.props('podeEscolher')).toBe(true);
    expect(cartao.props('teste').faltam).toBe(37);
    expect(cartao.props('teste').versoes.map(versao => versao.texto)).toEqual([
      'Oi, [Nome do contato]',
      'Olá!',
    ]);
  });

  it('com dois passos, diz de qual passo é cada cartão', async () => {
    AutomacoesAPI.duasVersoes.mockResolvedValue({
      data: { passos: [resultado('p1'), resultado('p2')] },
    });
    const wrapper = montar({
      ...RECEITA,
      passos: [passo('p1', 'Olá!'), passo('p2', 'Oi de novo')],
    });
    await flushPromises();
    expect(wrapper.findAllComponents(Cartao)).toHaveLength(2);
    expect(wrapper.find('[data-passo-com-versoes="p2"] p').text()).toContain(
      'DUAS_VERSOES.RESULTADO.AUTOMACAO.PASSO'
    );
  });

  it('"Ficar com esta" grava a versão e mostra o resultado novo', async () => {
    AutomacoesAPI.duasVersoes.mockResolvedValue({
      data: { passos: [resultado('p1')] },
    });
    AutomacoesAPI.escolherVersao.mockResolvedValue({
      data: resultado('p1', {
        estado: 'escolhida',
        vencedora: 2,
        escolhida_por: 'voce',
      }),
    });
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(Cartao).vm.$emit('escolher', 2);
    await flushPromises();

    expect(AutomacoesAPI.escolherVersao).toHaveBeenCalledWith(9, 'p1', 2);
    expect(wrapper.findComponent(Cartao).props('teste').estado).toBe(
      'escolhida'
    );
  });

  it('outra versão já escolhida (422): avisa e recarrega', async () => {
    AutomacoesAPI.duasVersoes.mockResolvedValue({
      data: { passos: [resultado('p1')] },
    });
    AutomacoesAPI.escolherVersao.mockRejectedValue({
      response: { status: 422 },
    });
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(Cartao).vm.$emit('escolher', 1);
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'DUAS_VERSOES.RESULTADO.AUTOMACAO.JA_ESCOLHIDA'
    );
    expect(AutomacoesAPI.duasVersoes).toHaveBeenCalledTimes(2);
  });

  it('a leitura que falhou mostra o cartão de erro, que tenta de novo', async () => {
    AutomacoesAPI.duasVersoes.mockRejectedValueOnce(new Error('rede'));
    const wrapper = montar();
    await flushPromises();

    const cartao = wrapper.findComponent(Cartao);
    expect(cartao.props('teste')).toBeNull();
    expect(cartao.props('carregando')).toBe(false);

    AutomacoesAPI.duasVersoes.mockResolvedValue({
      data: { passos: [resultado('p1')] },
    });
    cartao.vm.$emit('recarregar');
    await flushPromises();
    expect(wrapper.findComponent(Cartao).props('teste').passo).toBe('p1');
  });
});
