import { flushPromises, mount } from '@vue/test-utils';
import AprovacoesAPI from 'dashboard/api/autonomia/aprovacoes';
import AprovacoesPage from '../pages/AprovacoesPage.vue';

// #2931 — "Pedidos de aprovação": os pedidos abertos de quem olha, o do sino
// primeiro, e a resposta pela API. A resposta que perde a corrida mostra quem
// respondeu antes.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;
const rota = vi.hoisted(() => ({ query: {}, params: { accountId: 1 } }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t, locale: { value: 'pt_BR' } }),
}));
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock('dashboard/api/autonomia/aprovacoes', () => ({
  default: { get: vi.fn(), show: vi.fn(), responder: vi.fn() },
}));

const pedido = (id, mudanca = {}) => ({
  id,
  estado: 'aberto',
  pergunta: `Posso seguir ${id}?`,
  ate: '2026-11-13T12:00:00Z',
  automacao: { id: 3, nome: 'Desconto' },
  card: {
    id: 9,
    title: 'Card',
    currency: 'BRL',
    contact: { id: 1, name: 'Ana' },
  },
  conversa_id: 77,
  ...mudanca,
});

const stubs = {
  CrmKanbanCard: {
    name: 'CrmKanbanCard',
    props: ['card', 'comValor'],
    template: '<div data-card />',
  },
};
const montar = () =>
  mount(AprovacoesPage, { global: { stubs, mocks: { $t: t } } });

describe('AprovacoesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rota.query = {};
  });

  it('lista os pedidos abertos, com a pergunta e o link da conversa', async () => {
    AprovacoesAPI.get.mockResolvedValueOnce({
      data: { pedidos: [pedido(1), pedido(2)] },
    });
    const tela = montar();
    await flushPromises();

    const itens = tela.findAll('[data-pedido-real]');
    expect(itens).toHaveLength(2);
    expect(itens[0].find('[data-pedido-pergunta]').text()).toBe(
      'Posso seguir 1?'
    );
    expect(itens[0].find('[data-pedido-conversa]').exists()).toBe(true);
  });

  it('sem pedido, diz que nada espera', async () => {
    AprovacoesAPI.get.mockResolvedValueOnce({ data: { pedidos: [] } });
    const tela = montar();
    await flushPromises();

    expect(tela.find('[data-vazio]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.APROVACOES.VAZIO'
    );
  });

  it('o pedido do sino abre primeiro, mesmo já respondido por outra pessoa', async () => {
    rota.query = { pedido: '5' };
    AprovacoesAPI.get.mockResolvedValueOnce({ data: { pedidos: [pedido(1)] } });
    AprovacoesAPI.show.mockResolvedValueOnce({
      data: pedido(5, {
        estado: 'aprovado',
        decisao: { por_nome: 'Caio', por_mim: false },
      }),
    });
    const tela = montar();
    await flushPromises();

    const primeiro = tela.findAll('[data-pedido-real]')[0];
    expect(AprovacoesAPI.show).toHaveBeenCalledWith(5);
    expect(primeiro.find('[data-pedido-feito]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.PEDIDO.APROVADO_POR(Caio)'
    );
    expect(primeiro.find('[data-pedido-aprovar]').exists()).toBe(false);
  });

  it('aprovar manda a resposta e mostra o resultado', async () => {
    AprovacoesAPI.get.mockResolvedValueOnce({ data: { pedidos: [pedido(1)] } });
    AprovacoesAPI.responder.mockResolvedValueOnce({
      data: pedido(1, {
        estado: 'aprovado',
        decisao: { por_nome: 'Eu', por_mim: true },
      }),
    });
    const tela = montar();
    await flushPromises();

    await tela.find('[data-pedido-aprovar]').trigger('click');
    await flushPromises();

    expect(AprovacoesAPI.responder).toHaveBeenCalledWith(1, {
      aprovado: true,
      motivo: '',
    });
    expect(tela.find('[data-pedido-feito]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.PEDIDO.APROVADO'
    );
  });

  it('a resposta que chega depois de outra mostra o erro e quem respondeu', async () => {
    AprovacoesAPI.get.mockResolvedValueOnce({ data: { pedidos: [pedido(1)] } });
    AprovacoesAPI.responder.mockRejectedValueOnce({
      response: {
        data: {
          error: 'Este pedido já foi respondido ou encerrado.',
          pedido: pedido(1, {
            estado: 'recusado',
            decisao: { por_nome: 'Caio', por_mim: false, motivo: 'Caro' },
          }),
        },
      },
    });
    const tela = montar();
    await flushPromises();

    await tela.find('[data-pedido-recusar]').trigger('click');
    await tela.find('[data-pedido-confirmar-recusa]').trigger('click');
    await flushPromises();

    expect(AprovacoesAPI.responder).toHaveBeenCalledWith(1, {
      aprovado: false,
      motivo: '',
    });
    expect(tela.find('[data-pedido-erro]').text()).toBe(
      'Este pedido já foi respondido ou encerrado.'
    );
    expect(tela.find('[data-pedido-feito]').text()).toContain(
      'RECUSADO_POR(Caio)'
    );
  });

  it('o pedido do sino que não é mais da pessoa avisa', async () => {
    rota.query = { pedido: '8' };
    AprovacoesAPI.get.mockResolvedValueOnce({ data: { pedidos: [] } });
    AprovacoesAPI.show.mockRejectedValueOnce({ response: { status: 404 } });
    const tela = montar();
    await flushPromises();

    expect(tela.find('[data-nao-achou]').exists()).toBe(true);
  });
});
