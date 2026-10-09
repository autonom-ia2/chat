import { createApp, nextTick } from 'vue';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const loadComposable = () => import('./useAgentsList.js');

const agent = {
  id: 'clara',
  name: 'Clara',
  state: { code: 'E5' },
};

const mountComposable = composable => {
  let exposed;
  const app = createApp({
    setup() {
      exposed = composable();
      return () => null;
    },
  });
  const host = document.createElement('div');
  document.body.appendChild(host);
  app.mount(host);

  return {
    exposed,
    unmount: () => {
      app.unmount();
      host.remove();
    },
  };
};

describe('useAgentsList', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('carrega a projeção pela API account-scoped com cancelamento', async () => {
    const { useAgentsList } = await loadComposable();
    vi.spyOn(AutonomiaAgentsAPI, 'get').mockResolvedValue({
      data: { payload: [agent], meta: { total: 1 } },
    });
    const mounted = mountComposable(useAgentsList);

    await mounted.exposed.load();
    expect(AutonomiaAgentsAPI.get).toHaveBeenCalledWith({
      signal: expect.any(AbortSignal),
    });
    expect(mounted.exposed.rows.value).toEqual([agent]);
    expect(mounted.exposed.status.value).toBe('success');

    mounted.unmount();
  });

  it('envia somente o patch de status e rele o GET após a mutação', async () => {
    const { useAgentsList } = await loadComposable();
    vi.spyOn(AutonomiaAgentsAPI, 'update').mockResolvedValue({ data: {} });
    vi.spyOn(AutonomiaAgentsAPI, 'get').mockResolvedValue({
      data: { payload: [{ ...agent, state: { code: 'E6' } }] },
    });
    const mounted = mountComposable(useAgentsList);

    await mounted.exposed.updateStatus(agent, {
      status: 'paused',
      enabled: false,
    });

    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith('clara', {
      status: 'paused',
      enabled: false,
    });
    expect(AutonomiaAgentsAPI.get).toHaveBeenCalledTimes(1);
    expect(mounted.exposed.rows.value[0].state.code).toBe('E6');

    mounted.unmount();
  });

  it('conserva a projeção anterior quando o GET após o patch falha', async () => {
    const { useAgentsList } = await loadComposable();
    vi.spyOn(AutonomiaAgentsAPI, 'update').mockResolvedValue({ data: {} });
    vi.spyOn(AutonomiaAgentsAPI, 'get').mockRejectedValue(new Error('offline'));
    const mounted = mountComposable(useAgentsList);
    mounted.exposed.rows.value = [agent];

    await mounted.exposed.updateStatus(agent, {
      status: 'active',
      enabled: true,
    });

    expect(mounted.exposed.rows.value).toEqual([agent]);
    expect(mounted.exposed.isStale.value).toBe(true);
    expect(mounted.exposed.status.value).toBe('error');

    mounted.unmount();
  });

  it('não confunde uma resposta cancelada com uma lista vazia', async () => {
    const { useAgentsList } = await loadComposable();
    let resolveRequest;
    vi.spyOn(AutonomiaAgentsAPI, 'get').mockImplementation(
      () =>
        new Promise(resolve => {
          resolveRequest = resolve;
        })
    );
    const mounted = mountComposable(useAgentsList);
    const pending = mounted.exposed.load();
    mounted.exposed.abort();
    resolveRequest({ data: { payload: [] } });
    await pending;
    await nextTick();

    expect(mounted.exposed.rows.value).toEqual([]);
    expect(mounted.exposed.status.value).toBe('loading');

    mounted.unmount();
  });
});
