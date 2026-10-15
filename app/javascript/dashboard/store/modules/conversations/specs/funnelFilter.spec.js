import { applyPageFilters, filterByCrmPipeline } from '../helpers';
import getters from '../getters';
import actions from '../actions';

// Filtro "Funil" da lista (multifunil #1150): a conversa que chega pelo websocket só entra na lista filtrada se for do
// funil escolhido; "none" é "Sem assunto".
const conversa = (id, crmPipelineIds) => ({
  id,
  status: 'open',
  inbox_id: 1,
  labels: [],
  meta: { assignee: { id: 9 } },
  crm_pipeline_ids: crmPipelineIds,
});

describe('filtro Funil (#1150)', () => {
  describe('#filterByCrmPipeline', () => {
    it('sem funil escolhido não filtra, nem conversa sem o campo', () => {
      expect(filterByCrmPipeline(true, undefined, undefined)).toBe(true);
      expect(filterByCrmPipeline(true, '', [3])).toBe(true);
    });

    it('funil escolhido: só a conversa que tem o funil', () => {
      expect(filterByCrmPipeline(true, '3', [3, 5])).toBe(true);
      expect(filterByCrmPipeline(true, '3', [5])).toBe(false);
      expect(filterByCrmPipeline(true, '3', [])).toBe(false);
    });

    it('"Sem assunto": só a conversa sem funil', () => {
      expect(filterByCrmPipeline(true, 'none', [])).toBe(true);
      expect(filterByCrmPipeline(true, 'none', [3])).toBe(false);
    });

    it('conversa sem o campo não entra numa lista filtrada', () => {
      expect(filterByCrmPipeline(true, '3', undefined)).toBe(false);
      expect(filterByCrmPipeline(true, 'none', undefined)).toBe(false);
    });

    it('não reabre o que outro filtro já tirou', () => {
      expect(filterByCrmPipeline(false, '3', [3])).toBe(false);
    });
  });

  it('tempo real: a lista "Todas" filtrada por funil mostra só as conversas do funil', () => {
    const state = {
      allConversations: [conversa(1, [3]), conversa(2, [5]), conversa(3, [])],
    };
    const rootGetters = {
      getCurrentUser: { id: 9, accounts: [{ id: 1, role: 'administrator' }] },
      getCurrentAccountId: 1,
    };
    const lista = filtros =>
      getters
        .getAllStatusChats(
          state,
          {},
          {},
          rootGetters
        )({ status: 'open', ...filtros })
        .map(({ id }) => id);

    expect(lista({ crmPipelineId: '3' })).toEqual([1]);
    expect(lista({ crmPipelineId: 'none' })).toEqual([3]);
    expect(lista({})).toEqual([1, 2, 3]);
    expect(
      applyPageFilters(conversa(4, [3]), {
        status: 'open',
        crmPipelineId: '5',
      })
    ).toBe(false);
  });

  describe('#refreshConversationFunnel', () => {
    const contexto = ({ crmPipelineId, naLista }) => ({
      getters: {
        getChatListFilters: { crmPipelineId },
        getConversationById: () => (naLista ? conversa(42, []) : undefined),
      },
      dispatch: vi.fn(),
    });

    it('com filtro de funil, relê a conversa já listada', () => {
      const ctx = contexto({ crmPipelineId: '3', naLista: true });
      actions.refreshConversationFunnel(ctx, 42);

      expect(ctx.dispatch).toHaveBeenCalledWith('getConversation', 42);
    });

    it('sem filtro de funil, ou conversa fora da lista, não pede nada', () => {
      const semFiltro = contexto({ crmPipelineId: undefined, naLista: true });
      const foraDaLista = contexto({ crmPipelineId: '3', naLista: false });
      actions.refreshConversationFunnel(semFiltro, 42);
      actions.refreshConversationFunnel(foraDaLista, 42);

      expect(semFiltro.dispatch).not.toHaveBeenCalled();
      expect(foraDaLista.dispatch).not.toHaveBeenCalled();
    });
  });
});
