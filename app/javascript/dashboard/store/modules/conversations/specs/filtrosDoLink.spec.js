import { applyPageFilters, filterPeloFiltroDoLink } from '../helpers';
import getters from '../getters';
import actions, {
  RELEITURA_AO_VIVO_MS,
  PAGINAS_RELIDAS_NO_MAXIMO,
  cancelarReleituraDoFiltroDoLink,
} from '../actions';
import { mutations } from '../index';
import types from '../../../mutation-types';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

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

const esvaziarPromessas = async () => {
  for (let vez = 0; vez < 10; vez += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

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

    describe('com mais de uma página carregada', () => {
      // Cada leitura da API fica pendente até o teste responder, para controlar a ordem de chegada.
      const leiturasPendentes = () => {
        const fila = [];
        api.get.mockImplementation(
          params =>
            new Promise(resolve => {
              fila.push({ params, responder: ids => resolve(resposta(ids)) });
            })
        );
        return fila;
      };
      const contextoCom = ({ paginas, lista = [], ids = [] }) => ({
        commit: vi.fn(),
        dispatch: vi.fn(),
        state: estado(
          { daIa: true, page: paginas + 1, assigneeType: 'all' },
          { allConversations: lista, idsDoFiltroDoLink: ids }
        ),
        rootState: naCaixa({ da_ia: '1' }),
        rootGetters: paginaAtual(paginas),
      });
      const gravados = (commit, tipo) =>
        commit.mock.calls.filter(([nome]) => nome === tipo).map(([, v]) => v);
      const idsDe = conversas => conversas.map(({ id }) => id);
      let aviso;
      beforeEach(() => {
        aviso = vi.spyOn(emitter, 'emit');
      });
      afterEach(() => aviso.mockRestore());

      it('com 3 páginas, a conversa que saiu do filtro some e a rolagem e a paginação ficam', async () => {
        const lista = [1, 2, 3, 4, 5, 6, 7].map(id => conversa(id));
        const contexto = contextoCom({
          paginas: 3,
          lista,
          ids: idsDe(lista),
        });
        api.get.mockImplementation(async ({ page }) =>
          resposta({ 1: [1, 2], 2: [3, 4], 3: [6, 7] }[page])
        );

        await actions.releerFiltroDoLink(contexto);

        expect(api.get.mock.calls.map(([params]) => params.page)).toEqual([
          1, 2, 3,
        ]);
        expect(
          gravados(contexto.commit, types.SET_IDS_DO_FILTRO_DO_LINK)
        ).toEqual([{ ids: [1, 2, 3, 4, 6, 7], substituir: true }]);
        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST).map(idsDe)
        ).toEqual([[1, 2, 3, 4, 6, 7]]);
        const acoes = contexto.dispatch.mock.calls.map(([acao]) => acao);
        expect(acoes).not.toContain('updateChatListFilters');
        expect(acoes).not.toContain('fetchAllConversations');
        expect(acoes).not.toContain('conversationPage/reset');
        expect(aviso).not.toHaveBeenCalledWith(
          BUS_EVENTS.LISTA_DO_FILTRO_DO_LINK_NO_TOPO
        );
        // O mesmo que a leitura comum faz com o que chega: etiquetas e contatos.
        expect(contexto.dispatch).toHaveBeenCalledWith(
          'conversationLabels/setBulkConversationLabels',
          expect.arrayContaining([expect.objectContaining({ id: 6 })])
        );
        expect(gravados(contexto.commit, 'contacts/SET_CONTACTS')).toHaveLength(
          1
        );
      });

      it('com 6 páginas, a lista volta para a primeira página e a rolagem vai ao topo', async () => {
        const contexto = contextoCom({
          paginas: PAGINAS_RELIDAS_NO_MAXIMO + 1,
        });
        // A leitura da página 1 troca a lista.
        contexto.dispatch = vi.fn(async acao => {
          if (acao === 'fetchAllConversations') {
            contexto.state.allConversations = [conversa(1)];
          }
        });

        await actions.releerFiltroDoLink(contexto);

        expect(api.get).not.toHaveBeenCalled();
        expect(contexto.dispatch).toHaveBeenNthCalledWith(
          1,
          'updateChatListFilters',
          { page: 1, updatedWithin: null }
        );
        expect(contexto.dispatch).toHaveBeenNthCalledWith(
          2,
          'fetchAllConversations',
          { replaceExisting: true }
        );
        expect(aviso).toHaveBeenCalledWith(
          BUS_EVENTS.LISTA_DO_FILTRO_DO_LINK_NO_TOPO
        );
      });

      it('a lista fica intacta até a última página chegar, e troca de uma vez', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 3 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        fila[0].responder([1, 2]);
        fila[1].responder([3, 4]);
        await esvaziarPromessas();

        expect(contexto.commit).not.toHaveBeenCalled();

        fila[2].responder([5]);
        await releitura;

        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST).map(idsDe)
        ).toEqual([[1, 2, 3, 4, 5]]);
        expect(
          gravados(contexto.commit, types.SET_IDS_DO_FILTRO_DO_LINK)
        ).toHaveLength(1);
      });

      it('lista esvaziada no meio da releitura: as páginas que faltam são descartadas e nada grava', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 3 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        fila[0].responder([1, 2]);
        actions.emptyAllConversations({ commit: vi.fn() });
        fila[1].responder([3, 4]);
        fila[2].responder([5]);
        await releitura;

        expect(contexto.commit).not.toHaveBeenCalled();
      });

      it('lista lida de novo no meio (página 1, outro filtro): a releitura antiga não grava por cima', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        const leituraNova = actions.fetchAllConversations({
          commit: vi.fn(),
          dispatch: vi.fn(),
          state: estado({ esperandoMin: 30, page: 1 }),
        });
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        fila[2].responder([9]);
        await leituraNova;
        fila[0].responder([1]);
        fila[1].responder([2]);
        await releitura;

        expect(contexto.commit).not.toHaveBeenCalled();
      });

      it('com 6 páginas, se a leitura da página 1 não trocou a lista, a rolagem fica', async () => {
        const contexto = contextoCom({
          paginas: PAGINAS_RELIDAS_NO_MAXIMO + 1,
        });

        await actions.releerFiltroDoLink(contexto);

        expect(aviso).not.toHaveBeenCalledWith(
          BUS_EVENTS.LISTA_DO_FILTRO_DO_LINK_NO_TOPO
        );
      });

      it('troca de aba no meio da releitura: nada grava na aba nova, e ela é relida depois', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 3 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        actions.invalidateConversationListRequests({ commit: vi.fn() });
        fila.forEach(({ responder }) => responder([1]));
        await releitura;

        expect(contexto.commit).not.toHaveBeenCalled();
        vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('página seguinte pedida durante a releitura: a releitura é descartada e relida depois', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        const proximaPagina = actions.fetchAllConversations({
          commit: vi.fn(),
          dispatch: vi.fn(),
          state: estado({ daIa: true, page: 3, assigneeType: 'all' }),
        });
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        fila[2].responder([20]);
        await proximaPagina;
        fila[0].responder([1]);
        fila[1].responder([2]);
        await releitura;

        expect(contexto.commit).not.toHaveBeenCalled();
        vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('página seguinte que chega depois da troca da lista é descartada (a página não avança)', async () => {
        const fila = leiturasPendentes();
        const commitDaPagina = vi.fn();
        const proximaPagina = actions.fetchAllConversations({
          commit: commitDaPagina,
          dispatch: vi.fn(),
          state: estado({ daIa: true, page: 3, assigneeType: 'all' }),
        });
        await vi.waitFor(() => expect(fila).toHaveLength(1));
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(3));
        fila[1].responder([1]);
        fila[2].responder([2]);
        await releitura;
        fila[0].responder([30]);
        await proximaPagina;

        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST)
        ).toHaveLength(1);
        const gravadosDaPagina = commitDaPagina.mock.calls.map(
          ([tipo]) => tipo
        );
        expect(gravadosDaPagina).not.toContain(types.SET_ALL_CONVERSATION);
        expect(gravadosDaPagina).not.toContain(types.SET_IDS_DO_FILTRO_DO_LINK);
        expect(gravadosDaPagina).toContain(types.CLEAR_LIST_LOADING_STATUS);
      });

      it('evento do websocket durante uma releitura não começa outra: fica para depois dela', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        actions.updateConversation(contexto, conversa(5));
        vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS * 2);
        expect(releituras(contexto.dispatch)).toBe(0);

        fila.forEach(({ responder }) => responder([1]));
        await releitura;
        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST)
        ).toHaveLength(1);
        vi.advanceTimersByTime(RELEITURA_AO_VIVO_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('duas releituras: a mais velha, que chega depois, é descartada', async () => {
        const fila = leiturasPendentes();
        const primeira = contextoCom({ paginas: 2 });
        const segunda = contextoCom({ paginas: 2 });

        const velha = actions.releerFiltroDoLink(primeira);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        const nova = actions.releerFiltroDoLink(segunda);
        await vi.waitFor(() => expect(fila).toHaveLength(4));
        fila[2].responder([9]);
        fila[3].responder([10]);
        await nova;
        fila[0].responder([1]);
        fila[1].responder([2]);
        await velha;

        expect(primeira.commit).not.toHaveBeenCalled();
        expect(
          gravados(segunda.commit, types.SET_IDS_DO_FILTRO_DO_LINK)
        ).toEqual([{ ids: [9, 10], substituir: true }]);
      });

      it('a conversa que o websocket atualizou depois do pedido fica na versão da lista, dentro ou fora do filtro como estava', async () => {
        const lista = [
          conversa(4, { updated_at: 20 }),
          conversa(5, { updated_at: 20 }),
        ];
        const contexto = contextoCom({ paginas: 2, lista, ids: [4] });
        api.get.mockImplementation(async ({ page }) =>
          page === 1
            ? {
                data: {
                  data: {
                    payload: [
                      conversa(4, { updated_at: 10 }),
                      conversa(5, { updated_at: 10 }),
                    ],
                    meta: {},
                  },
                },
              }
            : resposta([9])
        );

        await actions.releerFiltroDoLink(contexto);

        expect(
          gravados(contexto.commit, types.SET_IDS_DO_FILTRO_DO_LINK)
        ).toEqual([{ ids: [9, 4], substituir: true }]);
        const [trocada] = gravados(
          contexto.commit,
          types.REPLACE_CONVERSATION_LIST
        );
        expect(trocada.find(({ id }) => id === 4).updated_at).toBe(20);
      });
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
  });
});
