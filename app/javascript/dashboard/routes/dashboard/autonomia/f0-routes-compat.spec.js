import { routes } from './autonomia.routes';

const store = vi.hoisted(() => ({
  getters: {
    'accounts/getAccount': vi.fn(),
  },
  dispatch: vi.fn(),
}));

vi.mock('dashboard/store', () => ({ default: store }));

const route = name => routes.find(item => item.name === name);

const enter = async (name, params = { accountId: '9' }) => {
  const next = vi.fn();
  await route(name).beforeEnter({ params }, {}, next);
  return next;
};

const account = ({ redesign = false, enabled = true } = {}) => ({
  id: 9,
  autonomia_agents_enabled: enabled,
  autonomia_agents_redesign: redesign,
  autonomia_agents_redesign_enabled: redesign,
});

describe('F0: entradas de Agentes e compatibilidade de rota', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.globalConfig = {
      AUTONOMIA_AGENTS_ENABLED: 'true',
      AUTONOMIA_AGENTS_REDESIGN: 'true',
    };
    store.getters['accounts/getAccount'].mockReturnValue(account());
  });

  it('preserva o nome, permissão e entrada global de convite', () => {
    const invite = route('autonomia_invite_connection');

    expect(invite).toMatchObject({
      name: 'autonomia_invite_connection',
      path: expect.stringContaining('autonomia/invite-connection'),
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    });
    expect(invite.beforeEnter).toBeUndefined();
  });

  it('mantém o gate antigo como pré-condição, mesmo com redesign por conta', async () => {
    window.globalConfig.AUTONOMIA_AGENTS_ENABLED = 'false';
    store.getters['accounts/getAccount'].mockReturnValue(
      account({ redesign: true })
    );

    const next = await enter('autonomia_agents_index');

    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume'
    );
  });

  it.each([false, true])(
    'permite a entrada legada nomeada com a flag de redesign %s',
    async redesign => {
      store.getters['accounts/getAccount'].mockReturnValue(
        account({ redesign })
      );

      const next = await enter('autonomia_agent_panel_legacy', {
        accountId: '9',
        agentId: '7',
        tab: 'tune',
      });

      expect(next).toHaveBeenCalledWith();
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/resume',
        expect.anything()
      );
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/start',
        expect.anything()
      );
    }
  );

  it('mantém a rota compatível no mesmo account/agente e com abas nomeadas', () => {
    const legacy = route('autonomia_agent_panel_legacy');

    expect(legacy).toMatchObject({
      name: 'autonomia_agent_panel_legacy',
      path: expect.stringContaining(
        'accounts/:accountId/agents/:agentId/legacy/:tab'
      ),
      meta: { permissions: expect.arrayContaining(['autonomia_view']) },
    });
    expect(legacy.path).toContain('(test|tune|performance)');
    expect(legacy.props({ params: { agentId: '7', tab: 'tune' } })).toEqual({
      agentId: '7',
      tab: 'tune',
    });
  });

  it('usa performance como default novo e preserva uma aba explícita', () => {
    store.getters['accounts/getAccount'].mockReturnValue(
      account({ redesign: true })
    );
    const panel = route('autonomia_agent_panel');

    expect(panel.props({ params: { agentId: '7' } })).toEqual({
      agentId: '7',
      tab: 'performance',
    });
    expect(panel.props({ params: { agentId: '7', tab: 'test' } })).toEqual({
      agentId: '7',
      tab: 'test',
    });
  });

  it('preserva test como default da entrada antiga quando o redesign está desligado', () => {
    const panel = route('autonomia_agent_panel');
    expect(panel.props({ params: { accountId: '9', agentId: '7' } })).toEqual({
      agentId: '7',
      tab: 'test',
    });
  });

  it.each([false, true])(
    'deixa a lista/painel legados disponíveis com redesign=%s sem desligar o produto',
    async redesign => {
      store.getters['accounts/getAccount'].mockReturnValue(
        account({ redesign })
      );

      const indexNext = await enter('autonomia_agents_index');
      const panelNext = await enter('autonomia_agent_panel', {
        accountId: '9',
        agentId: '7',
        tab: 'test',
      });

      expect(indexNext).toHaveBeenCalledWith();
      expect(panelNext).toHaveBeenCalledWith();
      expect(route('autonomia_agents_index').name).toBe(
        'autonomia_agents_index'
      );
    }
  );

  it('mantém o default test somente na entrada legada explícita', () => {
    const legacy = route('autonomia_agent_panel_legacy');

    expect(legacy.props({ params: { agentId: '7' } })).toEqual({
      agentId: '7',
      tab: 'test',
    });
  });
});
