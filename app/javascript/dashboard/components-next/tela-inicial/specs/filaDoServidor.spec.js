import ConversationApi from 'dashboard/api/inbox/conversation';
import { buscarFila, CONSULTA_DA_FILA, esperaDesde } from '../filaDoServidor';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { get: vi.fn() },
}));

describe('filaDoServidor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('pede as não atendidas abertas, minhas, da que espera há mais tempo', async () => {
    ConversationApi.get.mockResolvedValue({
      data: {
        data: {
          meta: { mine_count: 3, unassigned_count: 1, all_count: 9 },
          payload: [{ id: 4 }, { id: 7 }],
        },
      },
    });
    const fila = await buscarFila();
    expect(ConversationApi.get).toHaveBeenCalledWith({
      status: 'open',
      conversationType: 'unattended',
      assigneeType: 'me',
      sortBy: 'waiting_since_asc',
      page: 1,
    });
    expect(CONSULTA_DA_FILA.page).toBe(1);
    expect(fila).toEqual({
      esperamVoce: 3,
      esperamAlguem: 1,
      proxima: { id: 4 },
    });
  });

  it('lista vazia: zero e nenhuma próxima', async () => {
    ConversationApi.get.mockResolvedValue({
      data: {
        data: { meta: { mine_count: 0, unassigned_count: 0 }, payload: [] },
      },
    });
    expect(await buscarFila()).toEqual({
      esperamVoce: 0,
      esperamAlguem: 0,
      proxima: null,
    });
  });

  it('erro da api sobe para quem chamou', async () => {
    ConversationApi.get.mockRejectedValue(new Error('rede'));
    await expect(buscarFila()).rejects.toThrow('rede');
  });

  it('espera desde a última mensagem sem resposta, ou desde o início', () => {
    expect(esperaDesde({ waiting_since: 50, created_at: 10 })).toBe(50);
    expect(esperaDesde({ waiting_since: 0, created_at: 10 })).toBe(10);
    expect(esperaDesde(null)).toBe(0);
  });
});
