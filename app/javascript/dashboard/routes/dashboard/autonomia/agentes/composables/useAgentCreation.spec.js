import { createApp, nextTick, ref } from 'vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const loadComposable = () => import('./useAgentCreation.js');

const makeStore = () => ({
  getters: {
    'autonomiaBuildThreads/getThread': { id: 91, agent_id: 42 },
  },
  dispatch: vi.fn(() => Promise.resolve({ id: 91, status: 'processing' })),
});

const mountComposable = async options => {
  const { useAgentCreation } = await loadComposable();
  const store = makeStore();
  let exposed;
  const app = createApp({
    setup() {
      exposed = useAgentCreation(options);
      return () => null;
    },
  });
  app.config.globalProperties.$store = store;
  const host = document.createElement('div');
  document.body.appendChild(host);
  app.mount(host);

  return {
    exposed,
    store,
    unmount: () => {
      app.unmount();
      host.remove();
    },
  };
};

describe('useAgentCreation', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('inicia o rascunho uma vez com escolha, atuação e base', async () => {
    const mounted = await mountComposable({ step: 'choice' });

    await mounted.exposed.start({
      type: 'support',
      actuation: 'external',
    });

    expect(mounted.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      {
        type: 'support',
        actuation: 'external',
        with_knowledge: true,
      }
    );
    mounted.unmount();
  });

  it('retoma a thread account-scoped sem iniciar outra criação', async () => {
    const mounted = await mountComposable({ agentId: 42, step: 'tell' });
    mounted.store.dispatch.mockClear();

    await mounted.exposed.resume();

    expect(mounted.store.dispatch).toHaveBeenCalledTimes(1);
    expect(mounted.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      { agentId: 42 }
    );
    expect(mounted.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    mounted.unmount();
  });

  it('envia a resposta no thread hidratado, sem criar um thread novo', async () => {
    const mounted = await mountComposable({ agentId: 42, step: 'tell' });
    mounted.store.dispatch.mockClear();

    await mounted.exposed.send({ content: 'Atendo empresas.' });

    expect(mounted.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/send',
      { threadId: 91, content: 'Atendo empresas.' }
    );
    expect(mounted.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    mounted.unmount();
  });

  it('publica usando o agente atual e somente a configuração do Ligue', async () => {
    const publish = vi
      .spyOn(AutonomiaAgentsAPI, 'publish')
      .mockResolvedValue({ data: { id: 42, status: 'active' } });
    const mounted = await mountComposable({ agentId: 42, step: 'live' });

    await mounted.exposed.publish({
      inboxIds: [8, 9],
      responseWindow: 'always',
    });

    expect(publish).toHaveBeenCalledWith(42, {
      inboxIds: [8, 9],
      responseWindow: 'always',
    });
    mounted.unmount();
  });

  it('invalida o teste somente depois de salvar a apresentação com sucesso', async () => {
    const mounted = await mountComposable({ agentId: 42, step: 'test' });
    const previousResult = { reply: 'Resposta da apresentação antiga' };
    mounted.exposed.testValid.value = true;
    mounted.exposed.testResult.value = previousResult;
    mounted.store.dispatch.mockResolvedValue({
      id: 42,
      name: 'Clara nova',
      greeting: 'Olá, posso ajudar?',
    });

    await mounted.exposed.savePresentation({
      name: 'Clara nova',
      greeting: 'Olá, posso ajudar?',
    });

    expect(mounted.store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/update',
      {
        id: 42,
        name: 'Clara nova',
        greeting: 'Olá, posso ajudar?',
      }
    );
    expect(mounted.exposed.testValid.value).toBe(false);
    expect(mounted.exposed.testResult.value).toBeNull();
    mounted.unmount();
  });

  it('preserva o teste válido quando o PATCH da apresentação falha', async () => {
    const mounted = await mountComposable({ agentId: 42, step: 'test' });
    const previousResult = { reply: 'Resposta que ainda vale' };
    mounted.exposed.testValid.value = true;
    mounted.exposed.testResult.value = previousResult;
    mounted.store.dispatch.mockRejectedValueOnce(new Error('PATCH falhou'));

    await expect(
      mounted.exposed.savePresentation({
        name: 'Clara nova',
        greeting: 'Olá, posso ajudar?',
      })
    ).rejects.toThrow('PATCH falhou');

    expect(mounted.exposed.testValid.value).toBe(true);
    expect(mounted.exposed.testResult.value).toEqual(previousResult);
    mounted.unmount();
  });

  it('isola a thread antiga quando a rota troca do agente A para B', async () => {
    const agentId = ref(42);
    const mounted = await mountComposable({ agentId, step: 'tell' });

    expect(mounted.exposed.thread.value).toEqual({ id: 91, agent_id: 42 });

    agentId.value = 43;
    await nextTick();

    expect(mounted.exposed.agentId.value).toBe(43);
    expect(mounted.exposed.thread.value).toBeNull();
    expect(mounted.exposed.messages.value).toEqual([]);
    mounted.unmount();
  });
});
