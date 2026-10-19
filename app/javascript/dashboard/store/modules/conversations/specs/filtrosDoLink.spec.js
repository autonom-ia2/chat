import { applyPageFilters, filterPeloFiltroDoLink } from '../helpers';
import getters from '../getters';
import actions, {
  RELEITURA_AO_VIVO_MS,
  DESCARTES_SEGUIDOS_NO_MAXIMO,
  PAGINAS_RELIDAS_NO_MAXIMO,
  PISO_ENTRE_RELEITURAS_MS,
  TEMPO_LIMITE_DA_RELEITURA_MS,
  cancelarReleituraDoFiltroDoLink,
} from '../actions';
import { mutations } from '../index';
import types from '../../../mutation-types';
import * as Sentry from '@sentry/vue';

vi.mock('@sentry/vue', async importOriginal => ({
  ...(await importOriginal()),
  captureException: vi.fn(),
}));
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

    it('a conversa aberta continua na lista filtrada enquanto está aberta, mesmo fora do filtro; trocando de conversa, sai', () => {
      // O servidor parou de mandar a 7 (ela deixou de casar com o filtro), mas a pessoa está nela.
      const aberta = filterPeloFiltroDoLink(lista, true, [4, 9], 7);
      expect(aberta.map(({ id }) => id)).toEqual([4, 7, 9]);

      const outra = filterPeloFiltroDoLink(lista, true, [4, 9], 4);
      expect(outra.map(({ id }) => id)).toEqual([4, 9]);

      const nenhuma = filterPeloFiltroDoLink(lista, true, [4, 9], undefined);
      expect(nenhuma.map(({ id }) => id)).toEqual([4, 9]);
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

    it('a leitura silenciosa (releitura do filtro do link) não acende o carregando do rodapé; a comum acende', async () => {
      const commit = vi.fn();
      const state = { conversationFilters: { daIa: true, page: 1 } };
      api.get.mockResolvedValue(resposta([4]));

      await actions.fetchAllConversations(
        { commit, dispatch: vi.fn(), state },
        { replaceExisting: true, silenciosa: true }
      );
      expect(commit).not.toHaveBeenCalledWith(types.SET_LIST_LOADING_STATUS);
      expect(commit).toHaveBeenCalledWith(types.SET_IDS_DO_FILTRO_DO_LINK, {
        ids: [4],
        substituir: true,
      });

      await actions.fetchAllConversations({ commit, dispatch: vi.fn(), state });
      expect(commit).toHaveBeenCalledWith(types.SET_LIST_LOADING_STATUS);
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
        silenciosa: true,
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

      it('tráfego contínuo: releituras a pelo menos 10 s uma da outra, e a última vem depois do último evento', async () => {
        const inicios = [];
        const contexto = contextoCom({ paginas: 2 });
        contexto.dispatch = vi.fn(acao =>
          acao === 'releerFiltroDoLink'
            ? actions.releerFiltroDoLink(contexto)
            : undefined
        );
        api.get.mockImplementation(async ({ page }) => {
          if (page === 1) inicios.push(Date.now());
          return resposta([page]);
        });
        const comeco = Date.now();

        for (let segundo = 0; segundo < 35; segundo += 1) {
          actions.updateConversation(contexto, conversa(100 + segundo));
          // eslint-disable-next-line no-await-in-loop
          await vi.advanceTimersByTimeAsync(1000);
        }
        const ultimoEvento = Date.now() - 1000;
        await vi.advanceTimersByTimeAsync(PISO_ENTRE_RELEITURAS_MS * 2);

        expect(inicios[0] - comeco).toBe(RELEITURA_AO_VIVO_MS);
        inicios.slice(1).forEach((inicio, indice) => {
          expect(inicio - inicios[indice]).toBeGreaterThanOrEqual(
            PISO_ENTRE_RELEITURAS_MS
          );
        });
        expect(inicios.length).toBeLessThanOrEqual(5);
        expect(inicios.at(-1)).toBeGreaterThan(ultimoEvento);
      });

      it('página pendurada: passado o tempo-limite, a releitura é abandonada sem erro e o próximo evento relê', async () => {
        const erro = Sentry.captureException;
        erro.mockClear();
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        await vi.advanceTimersByTimeAsync(TEMPO_LIMITE_DA_RELEITURA_MS);
        await releitura;

        expect(fila.every(({ params }) => params)).toBe(true);
        expect(contexto.commit).not.toHaveBeenCalled();
        expect(erro).not.toHaveBeenCalled();
        actions.updateConversation(contexto, conversa(5));
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('a leitura pendurada recebe o signal que o tempo-limite cancela', async () => {
        const sinais = [];
        api.get.mockImplementation(
          (_, { signal }) =>
            new Promise(() => {
              sinais.push(signal);
            })
        );
        const releitura = actions.releerFiltroDoLink(
          contextoCom({ paginas: 2 })
        );
        await vi.waitFor(() => expect(sinais).toHaveLength(2));
        expect(sinais.some(({ aborted }) => aborted)).toBe(false);

        await vi.advanceTimersByTimeAsync(TEMPO_LIMITE_DA_RELEITURA_MS);
        await releitura;

        expect(sinais.every(({ aborted }) => aborted)).toBe(true);
      });

      it('mais de 5 páginas e a leitura pendurada: passado o tempo-limite, cancela a leitura e libera a próxima', async () => {
        const contexto = contextoCom({
          paginas: PAGINAS_RELIDAS_NO_MAXIMO + 1,
        });
        contexto.dispatch = vi.fn(acao =>
          acao === 'fetchAllConversations' ? new Promise(() => {}) : undefined
        );

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.advanceTimersByTimeAsync(TEMPO_LIMITE_DA_RELEITURA_MS);
        await releitura;

        expect(contexto.dispatch).toHaveBeenCalledWith(
          'invalidateConversationListRequests'
        );
        actions.updateConversation(contexto, conversa(5));
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

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
        // A leitura da página 1 grava a lista.
        contexto.dispatch = vi.fn(
          async acao => acao === 'fetchAllConversations'
        );

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
          { replaceExisting: true, silenciosa: true }
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
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
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
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      // Uma releitura que a rolagem descarta: a página seguinte é pedida enquanto as páginas da releitura vêm.
      const releituraDescartada = async (fila, contexto) => {
        const inicio = fila.length;
        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(inicio + 2));
        const proximaPagina = actions.fetchAllConversations({
          commit: vi.fn(),
          dispatch: vi.fn(),
          state: estado({ daIa: true, page: 3, assigneeType: 'all' }),
        });
        await vi.waitFor(() => expect(fila).toHaveLength(inicio + 3));
        fila.slice(inicio).forEach(({ responder }) => responder([1]));
        await Promise.all([releitura, proximaPagina]);
      };
      const releituraQueGrava = async (fila, contexto) => {
        const inicio = fila.length;
        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(inicio + 2));
        fila.slice(inicio).forEach(({ responder }) => responder([1]));
        await releitura;
      };

      it('releitura descartada seguidas vezes: a 5ª agenda uma última depois do piso; depois só no próximo evento', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        for (let vez = 1; vez <= DESCARTES_SEGUIDOS_NO_MAXIMO; vez += 1) {
          // eslint-disable-next-line no-await-in-loop
          await releituraDescartada(fila, contexto);
          vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
          expect(releituras(contexto.dispatch)).toBe(vez);
        }
        await releituraDescartada(fila, contexto);
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS * 3);
        expect(releituras(contexto.dispatch)).toBe(
          DESCARTES_SEGUIDOS_NO_MAXIMO
        );
        expect(contexto.commit).not.toHaveBeenCalled();

        actions.updateConversation(contexto, conversa(5));
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(
          DESCARTES_SEGUIDOS_NO_MAXIMO + 1
        );
      });

      it('releitura que grava zera a contagem: depois dela, o teto recomeça', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });
        const descartarVarias = async vezes => {
          for (let vez = 0; vez < vezes; vez += 1) {
            // eslint-disable-next-line no-await-in-loop
            await releituraDescartada(fila, contexto);
            vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
          }
        };

        await descartarVarias(DESCARTES_SEGUIDOS_NO_MAXIMO - 1);
        await releituraQueGrava(fila, contexto);
        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST)
        ).toHaveLength(1);
        const antes = releituras(contexto.dispatch);

        await descartarVarias(DESCARTES_SEGUIDOS_NO_MAXIMO - 1);

        expect(releituras(contexto.dispatch) - antes).toBe(
          DESCARTES_SEGUIDOS_NO_MAXIMO - 1
        );
      });

      it('caixa desmontada com a releitura em voo: a resposta dela não grava e não solta a releitura que veio depois', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const antiga = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        cancelarReleituraDoFiltroDoLink();
        const nova = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(4));
        fila[0].responder([1]);
        fila[1].responder([2]);
        await antiga;

        expect(contexto.commit).not.toHaveBeenCalled();
        // A nova segue em curso: outra releitura pedida agora fica para depois dela.
        await actions.releerFiltroDoLink(contexto);
        expect(fila).toHaveLength(4);

        fila[2].responder([3]);
        fila[3].responder([4]);
        await nova;
        expect(
          gravados(contexto.commit, types.REPLACE_CONVERSATION_LIST).map(idsDe)
        ).toEqual([[3, 4]]);
      });

      it('caixa desmontada com a releitura em voo: a resposta dela não conta como descarte nem pede outra', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const antiga = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        cancelarReleituraDoFiltroDoLink();
        const nova = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(4));
        fila[0].responder([1]);
        fila[1].responder([2]);
        await antiga;
        fila[2].responder([3]);
        fila[3].responder([4]);
        await nova;
        await vi.advanceTimersByTimeAsync(PISO_ENTRE_RELEITURAS_MS * 2);

        expect(releituras(contexto.dispatch)).toBe(0);
        expect(fila).toHaveLength(4);
      });

      it('relógio do sistema que volta não estica a espera: a releitura vem no piso', async () => {
        const contexto = contextoCom({ paginas: 1 });
        contexto.dispatch = vi.fn(
          async acao => acao === 'fetchAllConversations'
        );

        await actions.releerFiltroDoLink(contexto);
        vi.setSystemTime(Date.now() - 60 * 60 * 1000);
        actions.updateConversation(contexto, conversa(5));
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);

        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('com 6 páginas, a volta à página 1 que não gravou (a rolagem cancelou a leitura) conta como descartada e é relida depois', async () => {
        const contexto = contextoCom({
          paginas: PAGINAS_RELIDAS_NO_MAXIMO + 1,
        });
        // A leitura da página 1 foi cancelada: não gravou (a store pode ter trocado a lista por outro motivo).
        contexto.dispatch = vi.fn(async acao => {
          if (acao === 'fetchAllConversations') {
            contexto.state.allConversations = [conversa(1)];
          }
        });

        await actions.releerFiltroDoLink(contexto);
        expect(releituras(contexto.dispatch)).toBe(0);

        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
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
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('releitura pedida direto (um minuto, aba visível) durante outra: não começa junto, fica para depois dela', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const primeira = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        await actions.releerFiltroDoLink(contexto);
        await esvaziarPromessas();
        expect(fila).toHaveLength(2);

        fila[0].responder([1]);
        fila[1].responder([2]);
        await primeira;

        expect(
          gravados(contexto.commit, types.SET_IDS_DO_FILTRO_DO_LINK)
        ).toEqual([{ ids: [1, 2], substituir: true }]);
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(1);
      });

      it('o filtro deixou de valer enquanto as páginas vinham: nada grava e não relê de novo', async () => {
        const fila = leiturasPendentes();
        const contexto = contextoCom({ paginas: 2 });

        const releitura = actions.releerFiltroDoLink(contexto);
        await vi.waitFor(() => expect(fila).toHaveLength(2));
        contexto.state.appliedFilters = [{ attribute_key: 'status' }];
        fila.forEach(({ responder }) => responder([1]));
        await releitura;

        expect(contexto.commit).not.toHaveBeenCalled();
        vi.advanceTimersByTime(PISO_ENTRE_RELEITURAS_MS);
        expect(releituras(contexto.dispatch)).toBe(0);
      });

      it('os contatos recebem a lista inteira, inclusive a conversa que o websocket já atualizou', async () => {
        const lista = [conversa(4, { updated_at: 20 })];
        const contexto = contextoCom({ paginas: 2, lista, ids: [4] });
        api.get.mockImplementation(async ({ page }) =>
          page === 1 ? resposta([4]) : resposta([9])
        );

        await actions.releerFiltroDoLink(contexto);

        const [contatos] = gravados(contexto.commit, 'contacts/SET_CONTACTS');
        expect(contatos).toHaveLength(2);
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
        silenciosa: true,
      });
    });
  });
});
