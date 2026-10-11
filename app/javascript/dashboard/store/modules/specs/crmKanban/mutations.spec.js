import { actions, mutations } from '../../crmKanban';
import types from '../../../mutation-types';

describe('#crmKanban mutations', () => {
  it('appends cards to a single paginated stage without replacing other stages', () => {
    const state = {
      board: {
        pipeline: { id: 1 },
        stages: [
          { id: 1, cards: [{ id: 11 }], has_more: true, next_cursor: 11 },
          { id: 2, cards: [{ id: 21 }], has_more: false, next_cursor: null },
        ],
      },
    };

    mutations[types.APPEND_CRM_KANBAN_STAGE_CARDS](state, {
      stages: [
        {
          id: 1,
          cards: [{ id: 10 }, { id: 11 }],
          has_more: false,
          next_cursor: null,
        },
      ],
    });

    expect(state.board.stages).toEqual([
      {
        id: 1,
        cards: [{ id: 11 }, { id: 10 }],
        has_more: false,
        next_cursor: null,
      },
      { id: 2, cards: [{ id: 21 }], has_more: false, next_cursor: null },
    ]);
  });

  it('restores stages after failed drag-and-drop', () => {
    const state = {
      board: {
        pipeline: { id: 1 },
        stages: [{ id: 1, cards: [{ id: 11 }] }],
      },
    };
    const snapshot = [{ id: 1, cards: [{ id: 10 }, { id: 11 }] }];

    mutations[types.RESTORE_CRM_KANBAN_STAGES](state, snapshot);

    expect(state.board.stages).toEqual(snapshot);
  });

  it('updates a card in place and removes it from old stages', () => {
    const state = {
      board: {
        pipeline: { id: 1 },
        stages: [
          { id: 1, cards: [{ id: 11, title: 'A' }] },
          { id: 2, cards: [{ id: 21, title: 'B' }] },
        ],
      },
    };

    mutations[types.UPSERT_CRM_KANBAN_CARD](state, {
      id: 11,
      title: 'A+',
      stage_id: 2,
    });

    expect(state.board.stages).toEqual([
      { id: 1, cards: [] },
      {
        id: 2,
        cards: [
          { id: 11, title: 'A+', stage_id: 2 },
          { id: 21, title: 'B' },
        ],
      },
    ]);
  });

  it('upserts and removes pipelines from the active state', () => {
    const state = {
      pipelines: [{ id: 1, name: 'Funil A' }],
      board: { pipeline: { id: 1, name: 'Funil A' }, stages: [] },
    };

    mutations[types.UPSERT_CRM_KANBAN_PIPELINE](state, {
      id: 1,
      name: 'Funil A+',
    });
    mutations[types.UPSERT_CRM_KANBAN_PIPELINE](state, {
      id: 2,
      name: 'Funil B',
    });

    expect(state.pipelines).toEqual([
      { id: 2, name: 'Funil B' },
      { id: 1, name: 'Funil A+' },
    ]);
    expect(state.board.pipeline).toEqual({ id: 1, name: 'Funil A+' });

    mutations[types.REMOVE_CRM_KANBAN_PIPELINE](state, 1);

    expect(state.pipelines).toEqual([{ id: 2, name: 'Funil B' }]);
    expect(state.board).toEqual({ pipeline: null, stages: [] });
  });

  it('removes a stage from the board when the backend deletion succeeds', () => {
    const state = {
      board: {
        pipeline: { id: 1 },
        stages: [
          { id: 1, name: 'Novo', cards: [] },
          { id: 2, name: 'Proposta', cards: [] },
        ],
      },
    };

    mutations[types.REMOVE_CRM_KANBAN_STAGE](state, 1);

    expect(state.board.stages).toEqual([
      { id: 2, name: 'Proposta', cards: [] },
    ]);
  });

  it('sets list, follow-ups, and calendar state independently from the board', () => {
    const state = {
      cardsList: [],
      cardsListMeta: { count: 0 },
      followUps: [],
      followUpsMeta: { count: 0 },
      calendarEvents: [],
    };

    mutations[types.SET_CRM_CARDS_LIST](state, {
      cards: [{ id: 10, title: 'Lead' }],
      meta: { count: 1 },
    });
    mutations[types.UPSERT_CRM_CARD_IN_LIST](state, {
      id: 10,
      title: 'Lead atualizado',
    });
    mutations[types.SET_CRM_FOLLOW_UPS](state, {
      followUps: [{ id: 5, title: 'Retornar' }],
      meta: { count: 1 },
    });
    mutations[types.UPSERT_CRM_FOLLOW_UP](state, {
      id: 5,
      title: 'Retornar atualizado',
    });
    mutations[types.SET_CRM_CALENDAR_EVENTS](state, [{ id: 'follow_up_5' }]);

    expect(state.cardsList).toEqual([{ id: 10, title: 'Lead atualizado' }]);
    expect(state.cardsListMeta).toEqual({ count: 1 });
    expect(state.followUps).toEqual([{ id: 5, title: 'Retornar atualizado' }]);
    expect(state.followUpsMeta).toEqual({ count: 1 });
    expect(state.calendarEvents).toEqual([{ id: 'follow_up_5' }]);
  });

  it('applies realtime CRM card events only when they belong to the visible board and filters', () => {
    const commit = vi.fn();
    const state = {
      filters: {
        search: '',
        inboxId: '9',
        ownerId: '',
        priority: '',
        standalone: '',
        status: '',
        followUpStatus: '',
      },
      board: {
        pipeline: { id: 1 },
        stages: [],
      },
    };

    actions.handleRealtimeCardEvent(
      { commit, state },
      {
        event: 'crm.card.created',
        card: { id: 10, pipeline_id: 1, inbox_id: 9 },
      }
    );

    expect(commit).toHaveBeenCalledWith(types.UPSERT_CRM_KANBAN_CARD, {
      id: 10,
      pipeline_id: 1,
      inbox_id: 9,
    });

    commit.mockClear();
    actions.handleRealtimeCardEvent(
      { commit, state },
      {
        event: 'crm.card.updated',
        card: { id: 10, pipeline_id: 1, inbox_id: 8 },
      }
    );

    expect(commit).toHaveBeenCalledWith(types.REMOVE_CRM_KANBAN_CARD, 10);
  });

  it('removes realtime archived cards from the board', () => {
    const commit = vi.fn();
    const state = {
      filters: {
        search: '',
        inboxId: '',
        ownerId: '',
        priority: '',
        standalone: '',
        status: '',
        followUpStatus: '',
      },
      board: { pipeline: { id: 1 }, stages: [] },
    };

    actions.handleRealtimeCardEvent(
      { commit, state },
      {
        event: 'crm.card.archived',
        card: { id: 10, pipeline_id: 1, status: 'archived' },
      }
    );

    expect(commit).toHaveBeenCalledWith(types.REMOVE_CRM_KANBAN_CARD, 10);
  });

  it('syncs the customer badge of a contact on board and list cards (#1258)', () => {
    const state = {
      board: {
        stages: [
          {
            id: 1,
            cards: [
              { id: 11, contact: { id: 7, name: 'Ana', contact_type: 'lead' } },
              { id: 12, contact: { id: 8, name: 'Bia', contact_type: 'lead' } },
            ],
          },
        ],
      },
      cardsList: [{ id: 11, contact: { id: 7, contact_type: 'lead' } }],
    };

    mutations[types.SYNC_CRM_CARD_CONTACT](state, {
      id: 7,
      contact_type: 'customer',
      customer_since: 1773576000,
    });

    const [ana, bia] = state.board.stages[0].cards;
    expect(ana.contact).toEqual({
      id: 7,
      name: 'Ana',
      contact_type: 'customer',
      customer_since: 1773576000,
    });
    expect(bia.contact.contact_type).toBe('lead');
    expect(state.cardsList[0].contact.contact_type).toBe('customer');
  });

  it('ignores contact events without the customer fields', () => {
    const commit = vi.fn();
    actions.syncCardContact({ commit }, { id: 7, name: 'Ana' });
    expect(commit).not.toHaveBeenCalled();
  });
});
