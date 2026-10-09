import {
  actions,
  mutations,
  state as initialState,
} from '../../autonomiaBuildThreads';
import AutonomiaBuildThreadsAPI from '../../../../api/autonomia/buildThreads';

vi.mock('../../../../api/autonomia/buildThreads', () => ({
  default: {
    create: vi.fn(),
    show: vi.fn(),
    resume: vi.fn(),
    sendMessage: vi.fn(),
    retryBuild: vi.fn(),
  },
}));

describe('#autonomiaBuildThreads store', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    actions.stopPolling();
  });

  describe('actions', () => {
    it('não aplica um poll atrasado depois de fechar ou trocar a conversa de montagem', async () => {
      let finish;
      AutonomiaBuildThreadsAPI.show.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const moduleState = { ...initialState, thread: { id: 77, agent_id: 42 } };
      const commit = vi.fn();
      const dispatch = vi.fn();
      const request = actions.fetch(
        { commit, dispatch, state: moduleState },
        { threadId: 77 }
      );
      moduleState.thread = { id: 78, agent_id: 43 };
      finish({
        data: {
          payload: {
            id: 77,
            status: 'ready',
            agent_id: 42,
            messages: [{ role: 'assistant', content: 'Agente antigo' }],
          },
        },
      });
      await request;
      expect(commit).not.toHaveBeenCalledWith('SET_THREAD', expect.anything());
      expect(dispatch).not.toHaveBeenCalledWith('onSettled', expect.anything());
    });

    it('uma retomada cancelada não troca a projeção da conversa atual', async () => {
      let finish;
      AutonomiaBuildThreadsAPI.resume.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const abort = new AbortController();
      const commit = vi.fn();
      const dispatch = vi.fn();
      const moduleState = {
        ...initialState,
        uiFlags: { ...initialState.uiFlags },
      };
      const request = actions.resume(
        { commit, dispatch, state: moduleState },
        { agentId: 42, signal: abort.signal }
      );
      const rejected = expect(request).rejects.toMatchObject({
        name: 'AbortError',
      });
      abort.abort();
      finish({ data: { payload: { id: 77, agent_id: 42 } } });
      await rejected;
      expect(commit).not.toHaveBeenCalledWith('RESET');
      expect(commit).not.toHaveBeenCalledWith('SET_THREAD', expect.anything());
    });

    it('start opens a thread and maps the enveloped payload into the tracked slices', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.create.mockResolvedValue({
        data: {
          payload: {
            id: 3,
            agent_id: null,
            status: 'processing',
            state: 'next_question',
            messages: [{ role: 'assistant', content: 'Qual o objetivo?' }],
          },
        },
      });

      const payload = await actions.start(
        {
          commit,
          dispatch,
          state: { ...initialState, uiFlags: { ...initialState.uiFlags } },
        },
        { message: 'quero um agente de suporte' }
      );

      expect(AutonomiaBuildThreadsAPI.create).toHaveBeenCalledWith({
        agentId: undefined,
        message: 'quero um agente de suporte',
      });
      expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', { creating: true });
      expect(commit).toHaveBeenCalledWith('SET_THREAD', {
        id: 3,
        agent_id: null,
      });
      expect(commit).toHaveBeenCalledWith('SET_STATUS', 'processing');
      expect(commit).toHaveBeenCalledWith('SET_THREAD_STATE', 'next_question');
      expect(commit).toHaveBeenCalledWith('MERGE_MESSAGES', [
        { role: 'assistant', content: 'Qual o objetivo?' },
      ]);
      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'user',
        content: 'quero um agente de suporte',
      });
      expect(dispatch).toHaveBeenCalledWith(
        'poll',
        expect.objectContaining({ threadId: 3, epoch: expect.any(Number) })
      );
      expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', {
        creating: false,
      });
      expect(payload.id).toBe(3);
    });

    it('send posts the follow-up message, echoes the user turn and re-polls', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      const moduleState = { ...initialState, messages: [] };
      AutonomiaBuildThreadsAPI.sendMessage.mockResolvedValue({
        data: { payload: { id: 3, status: 'processing' } },
      });

      await actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'b2b' }
      );

      expect(AutonomiaBuildThreadsAPI.sendMessage).toHaveBeenCalledWith(
        3,
        'b2b',
        {},
        expect.any(String)
      );
      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'user',
        content: 'b2b',
      });
      expect(dispatch).toHaveBeenCalledWith(
        'poll',
        expect.objectContaining({ threadId: 3, epoch: expect.any(Number) })
      );
    });

    it('send reuses the same client_message_id when the same turn is retried after a failure', async () => {
      const moduleState = {
        ...initialState,
        messages: [],
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.sendMessage
        .mockRejectedValueOnce(new Error('network down'))
        .mockResolvedValueOnce({
          data: { payload: { id: 3, status: 'processing' } },
        });

      await actions
        .send(
          { commit, dispatch, state: moduleState },
          { threadId: 3, content: 'de novo' }
        )
        .catch(() => {});
      expect(moduleState.messages).toHaveLength(0);
      await actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'de novo' }
      );

      const [firstCall, secondCall] =
        AutonomiaBuildThreadsAPI.sendMessage.mock.calls;
      expect(firstCall[3]).toBe(secondCall[3]);
      expect(
        moduleState.messages.filter(
          message => message.role === 'user' && message.content === 'de novo'
        )
      ).toHaveLength(1);
    });

    it('send removes a conflict echo so the retry renders one local turn again', async () => {
      const moduleState = {
        ...initialState,
        messages: [],
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      const conflict = { response: { status: 409 } };
      AutonomiaBuildThreadsAPI.sendMessage
        .mockRejectedValueOnce(conflict)
        .mockResolvedValueOnce({
          data: { payload: { id: 3, status: 'processing' } },
        });

      await expect(
        actions.send(
          { commit, dispatch, state: moduleState },
          { threadId: 3, content: 'em andamento' }
        )
      ).rejects.toBe(conflict);
      expect(moduleState.messages).toHaveLength(0);

      await actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'em andamento' }
      );

      expect(
        moduleState.messages.filter(
          message =>
            message.role === 'user' && message.content === 'em andamento'
        )
      ).toHaveLength(1);
    });

    it('send mints a fresh client_message_id for a NEW turn with identical content', async () => {
      const moduleState = {
        ...initialState,
        messages: [],
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.sendMessage.mockResolvedValue({
        data: { payload: { id: 3, status: 'processing' } },
      });

      await actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'sim' }
      );
      await actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'sim' }
      );

      const [firstCall, secondCall] =
        AutonomiaBuildThreadsAPI.sendMessage.mock.calls;
      expect(firstCall[3]).not.toBe(secondCall[3]);
      expect(
        moduleState.messages.filter(
          message => message.role === 'user' && message.content === 'sim'
        )
      ).toHaveLength(2);
    });

    it('ignora a resposta tardia de send depois que a conversa é fechada', async () => {
      let finish;
      AutonomiaBuildThreadsAPI.sendMessage.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const moduleState = {
        ...initialState,
        uiFlags: { ...initialState.uiFlags },
        messages: [],
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      const request = actions.send(
        { commit, dispatch, state: moduleState },
        { threadId: 3, content: 'conversa antiga' }
      );

      mutations.RESET(moduleState);
      finish({
        data: { payload: { id: 3, status: 'processing', messages: [] } },
      });

      await expect(request).resolves.toBeNull();
      expect(moduleState.thread).toBeNull();
      expect(moduleState.messages).toEqual([]);
      expect(moduleState.uiFlags).toEqual({
        creating: false,
        sending: false,
        fetching: false,
      });
      expect(dispatch).not.toHaveBeenCalledWith('poll', expect.anything());
    });

    it('ignora a resposta tardia de retry depois que a conversa é fechada', async () => {
      let finish;
      AutonomiaBuildThreadsAPI.retryBuild.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const moduleState = {
        ...initialState,
        thread: { id: 3, agent_id: 42 },
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      const request = actions.retry(
        { commit, dispatch, state: moduleState },
        { threadId: 3 }
      );

      mutations.RESET(moduleState);
      finish({ data: { payload: { id: 3, status: 'processing' } } });

      await expect(request).resolves.toBeNull();
      expect(moduleState.thread).toBeNull();
      expect(dispatch).not.toHaveBeenCalledWith('poll', expect.anything());
    });

    it('ignora a resposta tardia de resume depois que a conversa é fechada', async () => {
      let finish;
      AutonomiaBuildThreadsAPI.resume.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const moduleState = {
        ...initialState,
        thread: { id: 3, agent_id: 42 },
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      const request = actions.resume(
        { commit, dispatch, state: moduleState },
        { agentId: 42 }
      );

      mutations.RESET(moduleState);
      finish({
        data: {
          payload: {
            id: 3,
            agent_id: 42,
            status: 'processing',
            messages: [{ role: 'assistant', content: 'antiga' }],
          },
        },
      });

      await expect(request).resolves.toBeNull();
      expect(moduleState.thread).toBeNull();
      expect(moduleState.messages).toEqual([]);
      expect(dispatch).not.toHaveBeenCalledWith('poll', expect.anything());
    });

    it('resume hydrates the nested thread and polls only while it is processing', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      const messages = [
        { id: 11, role: 'user', content: 'Somos uma escola' },
        { id: 12, role: 'assistant', content: 'Qual público você atende?' },
      ];
      const threadState = {
        needs_more_info: true,
        next_question: 'Qual público você atende?',
        turn: 2,
      };
      AutonomiaBuildThreadsAPI.resume.mockResolvedValue({
        data: {
          payload: {
            id: 77,
            agent_id: 42,
            status: 'processing',
            messages,
            state: threadState,
          },
        },
      });

      const payload = await actions.resume(
        {
          commit,
          dispatch,
          state: { ...initialState, uiFlags: { ...initialState.uiFlags } },
        },
        { agentId: 42 }
      );

      expect(AutonomiaBuildThreadsAPI.resume).toHaveBeenCalledWith(42);
      expect(commit).toHaveBeenCalledWith('RESET');
      expect(commit).toHaveBeenCalledWith('SET_THREAD', {
        id: 77,
        agent_id: 42,
      });
      expect(commit).toHaveBeenCalledWith('MERGE_MESSAGES', messages);
      expect(commit).toHaveBeenCalledWith('SET_STATUS', 'processing');
      expect(commit).toHaveBeenCalledWith('SET_THREAD_STATE', threadState);
      expect(dispatch).toHaveBeenCalledWith(
        'poll',
        expect.objectContaining({ threadId: 77, epoch: expect.any(Number) })
      );
      expect(dispatch).not.toHaveBeenCalledWith('start', expect.anything());
      expect(AutonomiaBuildThreadsAPI.create).not.toHaveBeenCalled();
      expect(AutonomiaBuildThreadsAPI.show).not.toHaveBeenCalled();
      expect(AutonomiaBuildThreadsAPI.sendMessage).not.toHaveBeenCalled();
      expect(AutonomiaBuildThreadsAPI.retryBuild).not.toHaveBeenCalled();
      expect(payload).toMatchObject({
        id: 77,
        agent_id: 42,
        status: 'processing',
        messages,
        state: threadState,
      });
    });

    it.each(['ready', 'open', 'failed'])(
      'resume hydrates a %s thread without phase side effects or creating a POST',
      async status => {
        const moduleState = {
          ...initialState,
          thread: { id: 12, agent_id: 42 },
          messages: [{ id: 10, role: 'user', content: 'stale' }],
          mergedCount: 1,
          status: 'processing',
          threadState: { turn: 1 },
          agent: { id: 42, name: 'Agente anterior' },
          phase: 'reviewing',
          error: 'stale',
          uiFlags: { ...initialState.uiFlags },
        };
        const commit = (type, payload) => mutations[type](moduleState, payload);
        const dispatch = vi.fn();
        const messages = [
          { id: 21, role: 'user', content: 'Atendemos escolas' },
          { id: 22, role: 'assistant', content: 'Entendi.' },
        ];
        const threadState = { needs_more_info: false, turn: 2 };
        AutonomiaBuildThreadsAPI.resume.mockResolvedValue({
          data: {
            payload: {
              id: 88,
              agent_id: 42,
              status,
              messages,
              state: threadState,
            },
          },
        });

        await actions.resume(
          { commit, dispatch, state: moduleState },
          { agentId: 42 }
        );

        expect(moduleState.thread).toEqual({ id: 88, agent_id: 42 });
        expect(moduleState.messages).toEqual(messages);
        expect(moduleState.mergedCount).toBe(messages.length);
        expect(moduleState.status).toBe(status);
        expect(moduleState.threadState).toEqual(threadState);
        expect(moduleState.agent).toBeNull();
        expect(moduleState.phase).toBe('interviewing');
        expect(moduleState.error).toBeNull();
        expect(dispatch).not.toHaveBeenCalled();
        expect(AutonomiaBuildThreadsAPI.create).not.toHaveBeenCalled();
        expect(AutonomiaBuildThreadsAPI.show).not.toHaveBeenCalled();
        expect(AutonomiaBuildThreadsAPI.sendMessage).not.toHaveBeenCalled();
        expect(AutonomiaBuildThreadsAPI.retryBuild).not.toHaveBeenCalled();
      }
    );

    it('preserves the last projection when the resume reader rejects', async () => {
      const moduleState = {
        ...initialState,
        thread: { id: 12, agent_id: 42 },
        messages: [{ id: 10, role: 'user', content: 'stale' }],
        mergedCount: 1,
        status: 'ready',
        threadState: { turn: 1 },
        agent: { id: 42, name: 'Agente anterior' },
        phase: 'reviewing',
        error: null,
        uiFlags: { ...initialState.uiFlags },
      };
      const commit = (type, payload) => mutations[type](moduleState, payload);
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.resume.mockRejectedValue({
        response: { status: 404, data: { message: 'Thread não encontrada' } },
      });

      await expect(
        actions.resume(
          { commit, dispatch, state: moduleState },
          { agentId: 42 }
        )
      ).rejects.toThrow('Thread não encontrada');

      expect(moduleState.thread).toEqual({ id: 12, agent_id: 42 });
      expect(moduleState.messages).toEqual([
        { id: 10, role: 'user', content: 'stale' },
      ]);
      expect(moduleState.status).toBe('ready');
      expect(moduleState.agent).toEqual({ id: 42, name: 'Agente anterior' });
      expect(moduleState.phase).toBe('reviewing');
      expect(moduleState.uiFlags.fetching).toBe(false);
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('preserves status and code from a resume reader rejection', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      const error = {
        response: {
          status: 401,
          data: { code: 'autonomia_forbidden', message: 'Sem permissão' },
        },
      };
      AutonomiaBuildThreadsAPI.resume.mockRejectedValue(error);

      await expect(
        actions.resume(
          {
            commit,
            dispatch,
            state: { ...initialState, uiFlags: { ...initialState.uiFlags } },
          },
          { agentId: 42 }
        )
      ).rejects.toMatchObject({
        response: error.response,
        status: 401,
        code: 'autonomia_forbidden',
      });
    });

    it('declareNoMaterials sends a silent gate signal with no_materials', () => {
      const dispatch = vi.fn();

      actions.declareNoMaterials(
        { dispatch },
        { threadId: 3, content: 'sem materiais' }
      );

      expect(dispatch).toHaveBeenCalledWith('send', {
        threadId: 3,
        content: 'sem materiais',
        extra: { no_materials: true },
        echo: false,
      });
    });

    it('completeMaterials sends a silent gate signal to close the instruction', () => {
      const dispatch = vi.fn();

      actions.completeMaterials(
        { dispatch },
        { threadId: 3, content: 'materiais prontos' }
      );

      expect(dispatch).toHaveBeenCalledWith('send', {
        threadId: 3,
        content: 'materiais prontos',
        echo: false,
        extra: { force_close: true },
      });
    });

    it('onSettled continues the interview when ready + needs_more_info', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      const $state = { messages: [{ role: 'user', content: 'suporte b2b' }] };

      await actions.onSettled(
        { commit, dispatch, state: $state },
        {
          status: 'ready',
          agent_id: null,
          state: { needs_more_info: true, next_question: 'Qual o tom de voz?' },
        }
      );

      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'assistant',
        content: 'Qual o tom de voz?',
      });
      expect(commit).toHaveBeenCalledWith('SET_PHASE', 'interviewing');
      expect(commit).toHaveBeenCalledWith('SET_STATUS', 'open');
      // No agent exists yet: never fetch one.
      expect(dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/show',
        expect.anything(),
        expect.anything()
      );
    });

    it('onSettled skips the fallback bubble when the merge already delivered the question as the last turn', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      const $state = {
        messages: [
          { role: 'user', content: 'suporte b2b' },
          { role: 'assistant', content: 'Qual o tom de voz?' },
        ],
      };

      await actions.onSettled(
        { commit, dispatch, state: $state },
        {
          status: 'ready',
          agent_id: null,
          state: { needs_more_info: true, next_question: 'Qual o tom de voz?' },
        }
      );

      expect(commit).not.toHaveBeenCalledWith(
        'APPEND_MESSAGE',
        expect.anything()
      );
    });

    it('onSettled still shows a legitimate REPEATED question (no global content dedupe)', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      // The Builder asked the same question earlier; the user answered
      // insufficiently and the Builder re-asks it — the bubble must show again.
      const $state = {
        messages: [
          { role: 'assistant', content: 'Qual o tom de voz?' },
          { role: 'user', content: 'hm' },
        ],
      };

      await actions.onSettled(
        { commit, dispatch, state: $state },
        {
          status: 'ready',
          agent_id: null,
          state: { needs_more_info: true, next_question: 'Qual o tom de voz?' },
        }
      );

      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'assistant',
        content: 'Qual o tom de voz?',
      });
    });

    it('onSettled fetches and stores the generated agent when the build completes', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn().mockResolvedValue({ id: 9, name: 'Suporte' });

      await actions.onSettled(
        { commit, dispatch },
        { status: 'ready', agent_id: 9, state: { needs_more_info: false } }
      );

      expect(commit).toHaveBeenCalledWith('SET_PHASE', 'reviewing');
      expect(dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 9, {
        root: true,
      });
      expect(commit).toHaveBeenCalledWith('SET_AGENT', {
        id: 9,
        name: 'Suporte',
      });
    });

    it('onSettled surfaces a visible error when the build failed', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();

      await actions.onSettled({ commit, dispatch }, { status: 'failed' });

      expect(commit).toHaveBeenCalledWith('SET_ERROR', 'failed');
    });

    it('onSettled is a no-op while the build is still processing', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();

      await actions.onSettled({ commit, dispatch }, { status: 'processing' });

      expect(dispatch).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });
  });

  describe('mutations', () => {
    it('RESET clears every tracked slice', () => {
      const state = {
        epoch: 8,
        thread: { id: 3 },
        messages: [{ role: 'user' }],
        mergedCount: 4,
        status: 'ready',
        threadState: 'turn',
        agent: { id: 9 },
        phase: 'reviewing',
        error: 'failed',
        uiFlags: { creating: true, sending: true, fetching: true },
      };
      mutations.RESET(state);
      expect(state).toEqual({
        epoch: 9,
        thread: null,
        messages: [],
        mergedCount: 0,
        status: null,
        threadState: {},
        agent: null,
        phase: 'interviewing',
        error: null,
        uiFlags: { creating: false, sending: false, fetching: false },
      });
    });

    it('APPEND_MESSAGE tags locally-authored turns so the merge can confirm them later', () => {
      const state = { messages: [] };
      mutations.APPEND_MESSAGE(state, { role: 'user', content: 'oi' });
      expect(state.messages).toEqual([
        { role: 'user', content: 'oi', local: true },
      ]);
    });

    it('MERGE_MESSAGES confirms pending local bubbles and appends new backend turns in order', () => {
      const state = {
        messages: [
          { role: 'user', content: 'oi', local: true },
          { role: 'assistant', content: 'Qual o objetivo?', local: true },
        ],
        mergedCount: 0,
      };
      mutations.MERGE_MESSAGES(state, [
        { role: 'user', content: 'oi' },
        { role: 'user', content: 'suporte' },
      ]);
      expect(state.messages).toEqual([
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'Qual o objetivo?', local: true },
        { role: 'user', content: 'suporte' },
      ]);
      expect(state.mergedCount).toBe(2);
    });

    it('MERGE_MESSAGES is a no-op when the backend list did not grow', () => {
      const state = {
        messages: [
          { role: 'user', content: 'oi' },
          { role: 'assistant', content: 'Qual o objetivo?', local: true },
        ],
        mergedCount: 1,
      };
      mutations.MERGE_MESSAGES(state, [{ role: 'user', content: 'oi' }]);
      expect(state.messages).toEqual([
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'Qual o objetivo?', local: true },
      ]);
      expect(state.mergedCount).toBe(1);
    });

    it('MERGE_MESSAGES keeps a REPEATED identical assistant turn instead of hiding it', () => {
      const state = { messages: [], mergedCount: 0 };
      mutations.MERGE_MESSAGES(state, [
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'Qual o objetivo?' },
      ]);
      // The user answered insufficiently and the Builder re-asked the SAME question.
      mutations.MERGE_MESSAGES(state, [
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'Qual o objetivo?' },
        { role: 'user', content: 'não sei' },
        { role: 'assistant', content: 'Qual o objetivo?' },
      ]);
      expect(state.messages).toHaveLength(4);
      expect(state.messages[3]).toEqual({
        role: 'assistant',
        content: 'Qual o objetivo?',
      });
      expect(state.mergedCount).toBe(4);
    });
  });
});
