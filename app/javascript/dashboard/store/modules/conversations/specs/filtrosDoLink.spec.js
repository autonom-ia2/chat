import {
  applyPageFilters,
  filterByEsperando,
  filterRecebidasDaIa,
} from '../helpers';
import getters from '../getters';
import actions from '../actions';
import { mutations } from '../index';
import types from '../../../mutation-types';

const api = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('../../../../api/inbox/conversation', () => ({ default: api }));

// Filtros pelo link na caixa (Números F2, #1883). A espera se confere no painel (waiting_since vem na conversa); as
// recebidas da IA, só o servidor sabe: a lista guarda os ids que ele mandou com o filtro ligado.
const AGORA = new Date('2026-10-19T12:00:00Z');
const segundos = data => Math.floor(data.getTime() / 1000);
const conversa = (id, waitingSince) => ({
  id,
  status: 'open',
  inbox_id: 1,
  labels: [],
  meta: {},
  waiting_since: waitingSince,
});

describe('filtros pelo link (#1883)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(AGORA);
  });

  afterEach(() => vi.useRealTimers());

  describe('#filterByEsperando', () => {
    const haMinutos = minutos => segundos(AGORA) - minutos * 60;

    it('sem o filtro não mexe na lista', () => {
      expect(filterByEsperando(true, null, 0)).toBe(true);
      expect(filterByEsperando(false, null, haMinutos(90))).toBe(false);
    });

    it('só entra quem espera há N minutos ou mais', () => {
      expect(filterByEsperando(true, 30, haMinutos(31))).toBe(true);
      expect(filterByEsperando(true, 30, haMinutos(30))).toBe(true);
      expect(filterByEsperando(true, 30, haMinutos(10))).toBe(false);
    });

    it('conversa respondida (waiting_since 0) não entra', () => {
      expect(filterByEsperando(true, 30, 0)).toBe(false);
      expect(filterByEsperando(true, 30, undefined)).toBe(false);
    });

    it('vale dentro do applyPageFilters', () => {
      const filtros = { status: 'open', esperandoMin: 30 };
      expect(applyPageFilters(conversa(1, haMinutos(45)), filtros)).toBe(true);
      expect(applyPageFilters(conversa(2, haMinutos(5)), filtros)).toBe(false);
    });
  });

  describe('recebidas da IA', () => {
    it('a lista lida com da_ia guarda os ids que o servidor mandou', async () => {
      api.get.mockResolvedValue({
        data: {
          data: { payload: [conversa(4, 0), conversa(9, 0)], meta: {} },
        },
      });
      const commit = vi.fn();
      const dispatch = vi.fn();
      const state = { conversationFilters: { daIa: true, page: 1 } };

      await actions.fetchAllConversations({ commit, dispatch, state });

      expect(commit).toHaveBeenCalledWith(
        types.ADD_IDS_RECEBIDAS_DA_IA,
        [4, 9]
      );
    });

    it('sem da_ia não guarda nada', async () => {
      api.get.mockResolvedValue({
        data: { data: { payload: [conversa(4, 0)], meta: {} } },
      });
      const commit = vi.fn();
      const state = { conversationFilters: { page: 1 } };

      await actions.fetchAllConversations({ commit, dispatch: vi.fn(), state });

      expect(commit).not.toHaveBeenCalledWith(
        types.ADD_IDS_RECEBIDAS_DA_IA,
        expect.anything()
      );
    });

    it('com o filtro, a conversa nova do websocket (fora dos ids) não entra na lista', () => {
      const lista = [conversa(4, 0), conversa(7, 0), conversa(9, 0)];

      expect(
        filterRecebidasDaIa(lista, true, [4, 9]).map(({ id }) => id)
      ).toEqual([4, 9]);
      expect(filterRecebidasDaIa(lista, true, [])).toEqual([]);
      expect(filterRecebidasDaIa(lista, undefined, [])).toBe(lista);
    });

    it('a conversa que o robô passou e espera pessoa entra mesmo fora dos ids (a marca vem no websocket)', () => {
      const passou = {
        ...conversa(11, 0),
        additional_attributes: { bot_handoff_waiting_since: '2026-10-19' },
      };
      const semMarca = { ...conversa(12, 0), additional_attributes: {} };

      expect(
        filterRecebidasDaIa([passou, semMarca], true, []).map(({ id }) => id)
      ).toEqual([11]);
    });

    it('os ids somam as páginas e saem quando a lista esvazia', () => {
      const state = { allConversations: [], idsRecebidasDaIa: [] };

      mutations[types.ADD_IDS_RECEBIDAS_DA_IA](state, [4, 9]);
      mutations[types.ADD_IDS_RECEBIDAS_DA_IA](state, [9, 12]);
      expect(getters.getIdsRecebidasDaIa(state)).toEqual([4, 9, 12]);

      mutations[types.EMPTY_ALL_CONVERSATION](state);
      expect(getters.getIdsRecebidasDaIa(state)).toEqual([]);
    });
  });
});
