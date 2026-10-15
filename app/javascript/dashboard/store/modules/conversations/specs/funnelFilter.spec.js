import { applyPageFilters, filterByCrmPipeline } from '../helpers';
import getters from '../getters';
import actions from '../actions';
import { mutations } from '../index';
import types from '../../../mutation-types';

const api = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock('../../../../api/inbox/conversation', () => ({ default: api }));

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

    it('card em funil oculto para a pessoa: não é "Sem assunto" nem entra em funil dela', () => {
      expect(filterByCrmPipeline(true, 'none', [], true)).toBe(false);
      expect(filterByCrmPipeline(true, '3', [], true)).toBe(false);
      expect(filterByCrmPipeline(true, '3', [3], true)).toBe(true);
      expect(
        applyPageFilters(
          { ...conversa(7, []), crm_pipeline_hidden: true },
          { status: 'open', crmPipelineId: 'none' }
        )
      ).toBe(false);
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

  describe('conversa que chega pelo websocket (sem os funis no payload)', () => {
    const estado = naLista => ({
      conversationFilters: { crmPipelineId: '3' },
      appliedFilters: [],
      allConversations: naLista ? [conversa(42, [])] : [],
    });

    it('conversa nova na lista: pede a leitura dos funis', () => {
      const dispatch = vi.fn();
      actions.addConversation(
        {
          commit: vi.fn(),
          dispatch,
          state: {
            currentInbox: null,
            appliedFilters: [],
            conversationFilters: { crmPipelineId: '3' },
          },
          rootState: { route: { name: 'home' } },
        },
        { ...conversa(42), meta: { sender: { id: 1 } } }
      );

      expect(dispatch).toHaveBeenCalledWith('refreshConversationFunnel', 42);
    });

    it('conversa atualizada que ainda não estava na lista: pede a leitura; já listada: não', () => {
      const novo = vi.fn();
      const listada = vi.fn();
      actions.updateConversation(
        {
          commit: vi.fn(),
          dispatch: novo,
          state: estado(false),
          rootGetters: {},
        },
        conversa(42, undefined)
      );
      actions.updateConversation(
        {
          commit: vi.fn(),
          dispatch: listada,
          state: estado(true),
          rootGetters: {},
        },
        conversa(42, undefined)
      );

      expect(novo).toHaveBeenCalledWith('refreshConversationFunnel', 42);
      expect(listada).not.toHaveBeenCalledWith('refreshConversationFunnel', 42);
    });
  });

  describe('#refreshConversationFunnel', () => {
    const contexto = ({
      crmPipelineId = '3',
      naLista = true,
      appliedFilters = [],
    }) => ({
      state: { conversationFilters: { crmPipelineId }, appliedFilters },
      getters: {
        getConversationById: () =>
          naLista ? conversa(42, undefined) : undefined,
      },
      commit: vi.fn(),
    });

    it('com filtro de funil, lê da API só os funis da conversa já listada', async () => {
      api.show.mockResolvedValue({
        data: { id: 42, crm_pipeline_ids: [3], crm_pipeline_hidden: true },
      });
      const ctx = contexto({});
      await actions.refreshConversationFunnel(ctx, 42);

      expect(api.show).toHaveBeenCalledWith(42);
      expect(ctx.commit).toHaveBeenCalledWith(
        types.SET_CONVERSATION_CRM_PIPELINE_IDS,
        {
          id: 42,
          crmPipelineIds: [3],
          crmPipelineHidden: true,
        }
      );
    });

    it('sem filtro, com pasta ou filtro avançado, ou conversa fora da lista, não pede nada', async () => {
      await actions.refreshConversationFunnel(
        contexto({ crmPipelineId: null }),
        42
      );
      await actions.refreshConversationFunnel(
        contexto({ appliedFilters: [{ attribute_key: 'status' }] }),
        42
      );
      await actions.refreshConversationFunnel(contexto({ naLista: false }), 42);

      expect(api.show).not.toHaveBeenCalled();
    });

    it('resposta fora de ordem é descartada: vale a leitura mais recente', async () => {
      let primeira;
      api.show
        .mockReturnValueOnce(
          new Promise(resolve => {
            primeira = resolve;
          })
        )
        .mockResolvedValueOnce({
          data: { id: 42, crm_pipeline_ids: [5], crm_pipeline_hidden: false },
        });
      const ctx = contexto({});

      const velha = actions.refreshConversationFunnel(ctx, 42);
      await actions.refreshConversationFunnel(ctx, 42);
      primeira({
        data: { id: 42, crm_pipeline_ids: [3], crm_pipeline_hidden: true },
      });
      await velha;

      expect(ctx.commit).toHaveBeenCalledTimes(1);
      expect(ctx.commit).toHaveBeenCalledWith(
        types.SET_CONVERSATION_CRM_PIPELINE_IDS,
        {
          id: 42,
          crmPipelineIds: [5],
          crmPipelineHidden: false,
        }
      );
    });

    it('falha da leitura não quebra e não grava nada; o próximo evento tenta de novo', async () => {
      api.show.mockRejectedValue(new Error('rede'));
      const ctx = contexto({});
      await actions.refreshConversationFunnel(ctx, 42);

      expect(ctx.commit).not.toHaveBeenCalled();
      const dispatch = vi.fn();
      actions.updateConversation(
        {
          commit: vi.fn(),
          dispatch,
          state: {
            conversationFilters: { crmPipelineId: '3' },
            appliedFilters: [],
            allConversations: [conversa(42, undefined)],
          },
          rootGetters: {},
        },
        conversa(42, undefined)
      );
      expect(dispatch).toHaveBeenCalledWith('refreshConversationFunnel', 42);
    });
  });

  describe('SET_CONVERSATION_CRM_PIPELINE_IDS', () => {
    it('grava só os funis, só em conversa que está na lista', () => {
      const state = {
        allConversations: [{ ...conversa(42, undefined), status: 'pending' }],
      };
      mutations[types.SET_CONVERSATION_CRM_PIPELINE_IDS](state, {
        id: 42,
        crmPipelineIds: [3],
      });
      mutations[types.SET_CONVERSATION_CRM_PIPELINE_IDS](state, {
        id: 99,
        crmPipelineIds: [3],
      });

      expect(state.allConversations).toHaveLength(1);
      expect(state.allConversations[0].crm_pipeline_ids).toEqual([3]);
      expect(state.allConversations[0].crm_pipeline_hidden).toBe(false);
      expect(state.allConversations[0].status).toBe('pending');
    });
  });
});
