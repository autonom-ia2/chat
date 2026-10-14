import { actions } from '../../autonomiaChannels';

// #1366 — ligar ou tirar canal muda o estado do agente no servidor (ativar junto; o último canal o
// para). A store relê o agente para a lista e a página não ficarem com o estado velho.
const api = vi.hoisted(() => ({
  get: vi.fn(),
  connect: vi.fn(),
  disconnect: vi.fn(),
}));
vi.mock('../../../../api/autonomia/channels', () => ({ default: api }));

const contexto = () => ({ commit: vi.fn(), dispatch: vi.fn() });

describe('#autonomiaChannels store (#1366)', () => {
  it('connects with ativar and reads the agent again', async () => {
    api.connect.mockResolvedValue({ data: { payload: [] } });
    const ctx = contexto();

    await actions.connect(ctx, { agentId: 7, inboxId: 3, ativar: true });

    expect(api.connect).toHaveBeenCalledWith(7, 3, { ativar: true });
    expect(ctx.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7, {
      root: true,
    });
  });

  it('does not read the agent again on a plain connect', async () => {
    api.connect.mockResolvedValue({ data: { payload: [] } });
    const ctx = contexto();

    await actions.connect(ctx, { agentId: 7, inboxId: 3 });

    expect(api.connect).toHaveBeenCalledWith(7, 3, { ativar: false });
    expect(ctx.dispatch).not.toHaveBeenCalledWith(
      'autonomiaAgents/show',
      expect.anything(),
      expect.anything()
    );
  });

  it('reads the agent again after a disconnect (the last channel stops it)', async () => {
    api.disconnect.mockResolvedValue({});
    const ctx = contexto();

    await actions.disconnect(ctx, { agentId: 7, inboxId: 3 });

    expect(ctx.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7, {
      root: true,
    });
  });

  it('keeps the disconnect done when only reading the agent again fails', async () => {
    api.disconnect.mockResolvedValue({});
    const ctx = contexto();
    ctx.dispatch.mockImplementation(async acao => {
      if (acao === 'autonomiaAgents/show') throw new Error('500');
    });

    await expect(
      actions.disconnect(ctx, { agentId: 7, inboxId: 3 })
    ).resolves.toBe(3);
  });
});
