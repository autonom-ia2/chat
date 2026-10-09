import {
  actions as channelActions,
  mutations as channelMutations,
} from '../../autonomiaChannels';
import AutonomiaChannelsAPI from '../../../../api/autonomia/channels';
import {
  actions as sourceActions,
  mutations as sourceMutations,
} from '../../autonomiaSources';
import AutonomiaSourcesAPI from '../../../../api/autonomia/sources';

vi.mock('../../../../api/autonomia/channels', () => ({
  default: {
    get: vi.fn(),
    connect: vi.fn(),
    disconnect: vi.fn(),
  },
}));

vi.mock('../../../../api/autonomia/sources', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
    resync: vi.fn(),
  },
}));

const deferred = () => {
  let resolve;
  const promise = new Promise(nextResolve => {
    resolve = nextResolve;
  });
  return { promise, resolve };
};

const newChannelState = () => ({
  epoch: 0,
  activeAgentId: null,
  connected: [],
  eligible: [],
  uiFlags: {
    fetching: false,
    connecting: false,
    disconnecting: false,
  },
});

const newSourceState = () => ({
  epoch: 0,
  activeAgentId: null,
  records: [],
  uiFlags: {
    fetchingList: false,
    creatingItem: false,
    deletingItem: false,
    resyncingItem: false,
  },
});

describe('isolamento das projeções dos agentes', () => {
  let channelState;
  let sourceState;
  let dispatchSources;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    channelState = newChannelState();
    sourceState = newSourceState();
    dispatchSources = (type, payload) => {
      if (type === 'schedulePoll') {
        return sourceActions.schedulePoll(
          { dispatch: dispatchSources, state: sourceState },
          payload
        );
      }
      if (type === 'fetch') {
        return sourceActions.fetch(
          {
            commit: (mutation, value) =>
              sourceMutations[mutation](sourceState, value),
            dispatch: dispatchSources,
            state: sourceState,
          },
          payload
        );
      }
      return undefined;
    };
  });

  afterEach(() => {
    channelActions.reset({
      commit: (mutation, value) =>
        channelMutations[mutation](channelState, value),
    });
    sourceActions.reset({
      commit: (mutation, value) =>
        sourceMutations[mutation](sourceState, value),
    });
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('não deixa a resposta tardia de canais do agente A sobrescrever B nem desligar o loading de B', async () => {
    const responseA = deferred();
    const responseB = deferred();
    AutonomiaChannelsAPI.get.mockImplementation(agentId =>
      agentId === 1 ? responseA.promise : responseB.promise
    );
    const commit = (mutation, value) =>
      channelMutations[mutation](channelState, value);
    const context = { commit, state: channelState };

    const requestA = channelActions.fetch(context, { agentId: 1 });
    const requestB = channelActions.fetch(context, { agentId: 2 });

    responseA.resolve({
      data: {
        payload: [{ inbox_id: 'caixa-a' }],
        eligible_inboxes: [],
      },
    });
    await requestA;
    expect(channelState.uiFlags.fetching).toBe(true);
    expect(channelState.connected).toEqual([]);

    responseB.resolve({
      data: {
        payload: [{ inbox_id: 'caixa-b' }],
        eligible_inboxes: [{ id: 22 }],
      },
    });
    await requestB;

    expect(channelState.connected).toEqual([{ inbox_id: 'caixa-b' }]);
    expect(channelState.eligible).toEqual([{ id: 22 }]);
    expect(channelState.uiFlags.fetching).toBe(false);
    expect(AutonomiaChannelsAPI.get.mock.calls[0][1].signal.aborted).toBe(true);
  });

  it('RESET invalida e cancela uma leitura de canais pendente', async () => {
    const pending = deferred();
    AutonomiaChannelsAPI.get.mockReturnValue(pending.promise);
    const commit = (mutation, value) =>
      channelMutations[mutation](channelState, value);

    const request = channelActions.fetch(
      { commit, state: channelState },
      { agentId: 7 }
    );
    channelActions.reset({ commit });
    pending.resolve({
      data: { payload: [{ inbox_id: 'caixa-antiga' }], eligible_inboxes: [] },
    });

    await expect(request).resolves.toBeNull();
    expect(channelState.activeAgentId).toBeNull();
    expect(channelState.connected).toEqual([]);
    expect(channelState.uiFlags.fetching).toBe(false);
  });

  it('não deixa a resposta tardia de fontes do agente A sobrescrever B nem desligar o loading de B', async () => {
    const responseA = deferred();
    const responseB = deferred();
    AutonomiaSourcesAPI.get.mockImplementation(agentId =>
      agentId === 1 ? responseA.promise : responseB.promise
    );
    const commit = (mutation, value) =>
      sourceMutations[mutation](sourceState, value);
    const context = { commit, dispatch: dispatchSources, state: sourceState };

    const requestA = sourceActions.fetch(context, { agentId: 1 });
    const requestB = sourceActions.fetch(context, { agentId: 2 });

    responseA.resolve({
      data: {
        payload: [
          {
            id: 1,
            reference: 'material-a',
            status: 'ready',
            review: { status: 'accepted' },
          },
        ],
      },
    });
    await requestA;
    expect(sourceState.uiFlags.fetchingList).toBe(true);
    expect(sourceState.records).toEqual([]);

    responseB.resolve({
      data: {
        payload: [
          {
            id: 2,
            reference: 'material-b',
            status: 'ready',
            review: { status: 'accepted' },
          },
        ],
      },
    });
    await requestB;

    expect(sourceState.records).toEqual([
      {
        id: 2,
        reference: 'material-b',
        status: 'ready',
        review: { status: 'accepted' },
      },
    ]);
    expect(sourceState.uiFlags.fetchingList).toBe(false);
    expect(AutonomiaSourcesAPI.get.mock.calls[0][1].signal.aborted).toBe(true);
  });

  it('cancela o timer de polling de A quando a projeção troca para B', async () => {
    AutonomiaSourcesAPI.get
      .mockResolvedValueOnce({
        data: {
          payload: [{ id: 1, status: 'processing', review: null }],
        },
      })
      .mockResolvedValueOnce({ data: { payload: [] } });
    const commit = (mutation, value) =>
      sourceMutations[mutation](sourceState, value);
    const context = { commit, dispatch: dispatchSources, state: sourceState };

    await sourceActions.fetch(context, { agentId: 1 });
    await sourceActions.fetch(context, { agentId: 2 });
    await vi.advanceTimersByTimeAsync(4000);

    expect(AutonomiaSourcesAPI.get).toHaveBeenCalledTimes(2);
    expect(sourceState.activeAgentId).toBe(2);
    expect(sourceState.records).toEqual([]);
  });

  it('preserva status e código quando a leitura de canais falha', async () => {
    const commit = (mutation, value) =>
      channelMutations[mutation](channelState, value);
    const error = {
      response: {
        status: 403,
        data: { code: 'inbox_forbidden', message: 'Sem permissão' },
      },
    };
    AutonomiaChannelsAPI.get.mockRejectedValue(error);

    await expect(
      channelActions.fetch({ commit, state: channelState }, { agentId: 7 })
    ).rejects.toMatchObject({
      response: error.response,
      status: 403,
      code: 'inbox_forbidden',
    });
  });
});
