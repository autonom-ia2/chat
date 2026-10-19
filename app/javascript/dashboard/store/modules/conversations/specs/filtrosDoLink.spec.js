import { applyPageFilters, filterPeloFiltroDoLink } from '../helpers';
import getters from '../getters';
import actions, {
  RELEITURA_AO_VIVO_MS,
  cancelarReleituraDoFiltroDoLink,
} from '../actions';
import { mutations } from '../index';
import types from '../../../mutation-types';

const api = vi.hoisted(() => ({ get: vi.fn(), show: vi.fn() }));
vi.mock('../../../../api/inbox/conversation', () => ({ default: api }));

// Filtros pelo link na caixa (Números F2, #1883). Quem decide o que entra é o servidor: a lista guarda os ids que ele
// mandou, e conversa nova ou mudada pelo websocket faz o servidor reler a lista.
const conversa = (id, extra = {}) => ({
  id,
  status: 'open',
  inbox_id: 1,
  labels: [],
  meta: { sender: { id: 1 } },
  updated_at: 10,
  ...extra,
});

const resposta = ids => ({
  data: { data: { payload: ids.map(id => conversa(id)), meta: {} } },
});

describe('filtros pelo link (#1883)', () => {
  describe('#filterPeloFiltroDoLink', () => {
    const lista = [conversa(4), conversa(7), conversa(9)];

    it('com o filtro, só o que o servidor mandou', () => {
      expect(
        filterPeloFiltroDoLink(lista, true, [4, 9]).map(({ id }) => id)
      ).toEqual([4, 9]);
      expect(filterPeloFiltroDoLink(lista, true, [])).toEqual([]);
    });

    it('sem o filtro, a lista fica como está', () => {
      expect(filterPeloFiltroDoLink(lista, false, [])).toBe(lista);
    });

    it('a marca de espera na conversa não decide nada no painel (o servidor decide)', () => {
      const comMarca = conversa(11, {
        additional_attributes: { bot_handoff_waiting_since: '2026-10-19' },
      });
      expect(filterPeloFiltroDoLink([comMarca], true, [])).toEqual([]);
    });

    it('a espera não é reaplicada com o relógio do navegador', () => {
      const respondida = conversa(5, { waiting_since: 0 });
      expect(
        applyPageFilters(respondida, { status: 'open', esperandoMin: 30 })
      ).toBe(true);
    });
  });

  describe('ids do servidor', () => {
    beforeEach(() => api.get.mockReset());

    it('a lista lida com o filtro guarda os ids; a releitura substitui', async () => {
      const commit = vi.fn();
      const state = { conversationFilters: { esperandoMin: 30, page: 1 } };
      api.get.mockResolvedValueOnce(resposta([4, 9]));

      await actions.fetchAllConversations({ commit, dispatch: vi.fn(), state });
      expect(commit).toHaveBeenCalledWith(types.SET_IDS_DO_FILTRO_DO_LINK, {
        ids: [4, 9],
        substituir: false,
      });

      api.get.mockResolvedValueOnce(resposta([9]));
      await actions.fetchAllConversations(
        { commit, dispatch: vi.fn(), state },
        { replaceExisting: true }
      );
      expect(commit).toHaveBeenCalledWith(types.SET_IDS_DO_FILTRO_DO_LINK, {
        ids: [9],
        substituir: true,
      });
    });

    it('sem o filtro não guarda nada', async () => {
      const commit = vi.fn();
      api.get.mockResolvedValueOnce(resposta([4]));

      await actions.fetchAllConversations({
        commit,
        dispatch: vi.fn(),
        state: { conversationFilters: { page: 1 } },
      });

      expect(commit).not.toHaveBeenCalledWith(
        types.SET_IDS_DO_FILTRO_DO_LINK,
        expect.anything()
      );
    });

    it('página seguinte soma, releitura troca, lista vazia limpa', () => {
      const state = { allConversations: [], idsDoFiltroDoLink: [] };

      mutations[types.SET_IDS_DO_FILTRO_DO_LINK](state, { ids: [4, 9] });
      mutations[types.SET_IDS_DO_FILTRO_DO_LINK](state, { ids: [9, 12] });
      expect(getters.getIdsDoFiltroDoLink(state)).toEqual([4, 9, 12]);

      mutations[types.SET_IDS_DO_FILTRO_DO_LINK](state, {
        ids: [12],
        substituir: true,
      });
      expect(getters.getIdsDoFiltroDoLink(state)).toEqual([12]);

      mutations[types.EMPTY_ALL_CONVERSATION](state);
      expect(getters.getIdsDoFiltroDoLink(state)).toEqual([]);
    });
  });

  describe('releitura ao vivo', () => {
    beforeEach(() => {
      vi.useFakeTimers();
      api.get.mockReset();
      cancelarReleituraDoFiltroDoLink();
    });
    afterEach(() => {
      cancelarReleituraDoFiltroDoLink();
      vi.useRealTimers();
    });

    const naCaixa = query => ({ route: { name: 'home', query } });
    const estado = (filtros, extra = {}) => ({
      allConversations: [],
      appliedFilters: [],
      listLoadingStatus: false,
      idsDoFiltroDoLink: [],
      conversationFilters: filtros,
      ...extra,
    });
    const paginaAtual = pagina => ({
      'conversationPage/getCurrentPageFilter': () => pagina,
    });
    const releituras = dispatch =>
      dispatch.mock.calls.filter(([acao]) => acao === 'releerFiltroDoLink')
        .length;

    it('uma rajada de eventos do websocket vira uma releitura só, depois do intervalo', () => {
      const dispatch = vi.fn();
      const contexto = {
        commit: vi.fn(),
        dispatch,
        state: estado({ daIa: true }),
        rootState: naCaixa({ da_ia: '1' }),
        rootGetters: {},
      };

      actions.updateConversation(contexto, conversa(4));
      actions.updateConversation(contexto, conversa(7));
      actions.addConversation(contexto, conversa(8));
      expect(releituras(dispatch)).toBe(0);

      vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS);
      expect(releituras(dispatch)).toBe(1);

      actions.updateConversation(contexto, conversa(9));
      vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS);
      expect(releituras(dispatch)).toBe(2);
    });

    it('sem o filtro do link, com o filtro avançado, ou fora da caixa (CRM), não relê', () => {
      const dispatch = vi.fn();
      const contexto = { commit: vi.fn(), dispatch, rootGetters: {} };
      const link = naCaixa({ esperando_min: '30' });

      actions.updateConversation(
        { ...contexto, state: estado({}), rootState: naCaixa({}) },
        conversa(4)
      );
      actions.updateConversation(
        {
          ...contexto,
          state: estado({ esperandoMin: 30 }, { appliedFilters: [{}] }),
          rootState: link,
        },
        conversa(5)
      );
      actions.updateConversation(
        {
          ...contexto,
          state: estado({ esperandoMin: 30 }),
          rootState: { route: { name: 'crm_kanban_index', query: {} } },
        },
        conversa(6)
      );
      vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS * 2);

      expect(releituras(dispatch)).toBe(0);
    });

    it('só a primeira página carregada: a releitura volta à página 1 e troca a lista', async () => {
      const dispatch = vi.fn();

      await actions.releerFiltroDoLink({
        dispatch,
        commit: vi.fn(),
        state: estado({ esperandoMin: 30, page: 2, assigneeType: 'me' }),
        rootState: naCaixa({ esperando_min: '30' }),
        rootGetters: paginaAtual(1),
      });

      expect(dispatch).toHaveBeenNthCalledWith(1, 'updateChatListFilters', {
        page: 1,
        updatedWithin: null,
      });
      expect(dispatch).toHaveBeenNthCalledWith(2, 'fetchAllConversations', {
        replaceExisting: true,
      });
    });

    it('com mais páginas carregadas, soma a primeira página sem mexer na rolagem', async () => {
      const dispatch = vi.fn().mockResolvedValue({ id: 1 });
      const commit = vi.fn();
      api.get.mockResolvedValueOnce(resposta([12]));

      await actions.releerFiltroDoLink({
        dispatch,
        commit,
        state: estado({ daIa: true, page: 4, assigneeType: 'all' }),
        rootState: naCaixa({ da_ia: '1' }),
        rootGetters: paginaAtual(3),
      });

      expect(api.get).toHaveBeenCalledWith(
        expect.objectContaining({ daIa: true, page: 1 })
      );
      expect(commit).toHaveBeenCalledWith(types.SET_IDS_DO_FILTRO_DO_LINK, {
        ids: [12],
        substituir: false,
      });
      expect(commit).toHaveBeenCalledWith(types.SET_ALL_CONVERSATION, [
        expect.objectContaining({ id: 12 }),
      ]);
      const acoes = dispatch.mock.calls.map(([acao]) => acao);
      expect(acoes).not.toContain('updateChatListFilters');
      expect(acoes).not.toContain('fetchAllConversations');
      expect(acoes).not.toContain('conversationPage/reset');
    });

    it('com mais páginas, se a lista mudou enquanto a leitura vinha, a resposta é descartada', async () => {
      const commit = vi.fn();
      const state = estado({ daIa: true, page: 4, assigneeType: 'all' });
      api.get.mockImplementationOnce(async () => {
        state.conversationFilters = { esperandoMin: 30, page: 1 };
        return resposta([12]);
      });

      await actions.releerFiltroDoLink({
        dispatch: vi.fn(),
        commit,
        state,
        rootState: naCaixa({ da_ia: '1' }),
        rootGetters: paginaAtual(3),
      });

      expect(api.get).toHaveBeenCalledTimes(1);
      expect(commit).not.toHaveBeenCalled();
    });

    it('com a próxima página chegando, não cancela a rolagem: espera, e relê quando ela chega', async () => {
      const state = estado({ daIa: true }, { listLoadingStatus: true });
      const contexto = {
        commit: vi.fn(),
        state,
        rootState: naCaixa({ da_ia: '1' }),
        rootGetters: paginaAtual(1),
      };
      // O dispatch roda a releitura agendada de verdade.
      contexto.dispatch = vi.fn(acao =>
        acao === 'releerFiltroDoLink'
          ? actions.releerFiltroDoLink(contexto)
          : undefined
      );
      const buscas = () =>
        contexto.dispatch.mock.calls.filter(
          ([acao]) => acao === 'fetchAllConversations'
        ).length;

      await actions.releerFiltroDoLink(contexto);
      expect(buscas()).toBe(0);

      state.listLoadingStatus = false;
      await vi.advanceTimersByTimeAsync(RELEITURA_AO_VIVO_MS);

      expect(buscas()).toBe(1);
      expect(contexto.dispatch).toHaveBeenCalledWith('fetchAllConversations', {
        replaceExisting: true,
      });
    });

    describe('com mais páginas, a soma da primeira página', () => {
      const somar = async ({ payload, meta = {}, lista = [], ids = [] }) => {
        const commit = vi.fn();
        api.get.mockResolvedValueOnce({ data: { data: { payload, meta } } });
        await actions.releerFiltroDoLink({
          dispatch: vi.fn(),
          commit,
          state: estado(
            { daIa: true, page: 3, assigneeType: 'all' },
            { allConversations: lista, idsDoFiltroDoLink: ids }
          ),
          rootState: naCaixa({ da_ia: '1' }),
          rootGetters: paginaAtual(2),
        });
        const chamada = tipo =>
          commit.mock.calls.find(([nome]) => nome === tipo)?.[1];
        return {
          ids: chamada(types.SET_IDS_DO_FILTRO_DO_LINK),
          conversas: chamada(types.SET_ALL_CONVERSATION),
        };
      };

      it('quando a página 1 traz tudo o que a aba tem, ela troca os ids (o que saiu do filtro sai)', async () => {
        const { ids } = await somar({
          payload: [conversa(12)],
          meta: { all_count: 1 },
        });
        expect(ids).toEqual({ ids: [12], substituir: true });

        const vazia = await somar({ payload: [], meta: { all_count: 0 } });
        expect(vazia.ids).toEqual({ ids: [], substituir: true });
      });

      it('quando a aba tem mais que a página 1, só soma', async () => {
        const { ids } = await somar({
          payload: [conversa(12)],
          meta: { all_count: 40 },
        });
        expect(ids).toEqual({ ids: [12], substituir: false });
      });

      it('não volta ao estado antigo a conversa que o websocket já atualizou', async () => {
        const { conversas } = await somar({
          payload: [
            conversa(4, { updated_at: 10 }),
            conversa(7, { updated_at: 30 }),
          ],
          lista: [
            conversa(4, { updated_at: 20 }),
            conversa(7, { updated_at: 20 }),
          ],
        });
        expect(conversas.map(({ id }) => id)).toEqual([7]);
      });

      it('a conversa que o websocket atualizou continua dentro ou fora do filtro como estava', async () => {
        const lista = [
          conversa(4, { updated_at: 20 }),
          conversa(5, { updated_at: 20 }),
        ];
        const payload = [
          conversa(4, { updated_at: 10 }),
          conversa(5, { updated_at: 10 }),
          conversa(9, { updated_at: 30 }),
        ];

        const { ids } = await somar({
          payload,
          lista,
          ids: [4],
          meta: { all_count: 3 },
        });

        expect(ids).toEqual({ ids: [9, 4], substituir: true });
      });

      it('duas somas fora de ordem: a resposta mais velha, que chega depois, é descartada', async () => {
        let responderPrimeira;
        api.get
          .mockImplementationOnce(
            () =>
              new Promise(resolve => {
                responderPrimeira = () => resolve(resposta([4]));
              })
          )
          .mockResolvedValueOnce(resposta([9]));
        const commit = vi.fn();
        const contexto = {
          dispatch: vi.fn(),
          commit,
          state: estado({ daIa: true, page: 3, assigneeType: 'all' }),
          rootState: naCaixa({ da_ia: '1' }),
          rootGetters: paginaAtual(2),
        };

        const primeira = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(api.get).toHaveBeenCalledTimes(1));
        await actions.releerFiltroDoLink(contexto);
        responderPrimeira();
        await primeira;

        const idsGravados = commit.mock.calls
          .filter(([tipo]) => tipo === types.SET_IDS_DO_FILTRO_DO_LINK)
          .map(([, valor]) => valor.ids);
        expect(idsGravados).toEqual([[9]]);
      });
    });
  });
});
