// Menu Agentes da barra lateral (#1181). Com a flag desligada, o item tem de ser
// exatamente o do main (o objeto abaixo é cópia literal do bloco que estava no
// Sidebar.vue). Com a flag ligada, um item só, "Agentes", que fica marcado na
// lista, no Construtor e na página do agente.
import { agentsSidebarItems } from '../utils/agentsSidebar';

const t = key => key;
const accountScopedRoute = name => ({ name, params: { accountId: 1 } });
const items = ({ isVisible = true, journeyOn = false } = {}) =>
  agentsSidebarItems({ isVisible, journeyOn, t, accountScopedRoute });

// Cópia literal do Sidebar.vue do main (origin/main, bloco `autonomiaAgentsEnabled`).
const ITEM_DO_MAIN = {
  name: 'Agents',
  label: t('SIDEBAR.AGENTS_AUTONOMIA'),
  icon: 'i-lucide-bot',
  activeOn: [
    'autonomia_agents_index',
    'autonomia_agents_builder',
    'autonomia_agent_panel',
  ],
  children: [
    {
      name: 'My Agents',
      label: t('SIDEBAR.AGENTS_HUB'),
      to: accountScopedRoute('autonomia_agents_index'),
      activeOn: ['autonomia_agents_index', 'autonomia_agent_panel'],
    },
    {
      name: 'Agent Builder',
      label: t('SIDEBAR.AGENTS_BUILDER'),
      to: accountScopedRoute('autonomia_agents_builder'),
      activeOn: ['autonomia_agents_builder'],
    },
  ],
};

describe('menu Agentes da barra lateral', () => {
  it('não aparece para quem não vê os Agentes, com a flag ligada ou desligada', () => {
    expect(items({ isVisible: false })).toEqual([]);
    expect(items({ isVisible: false, journeyOn: true })).toEqual([]);
  });

  it('com a flag desligada, é idêntico ao item do main', () => {
    expect(items()).toStrictEqual([ITEM_DO_MAIN]);
  });

  it('com a flag ligada, é um item só, "Agentes", que leva à lista', () => {
    expect(items({ journeyOn: true })).toStrictEqual([
      {
        name: 'Agents',
        label: 'AGENTS.JORNADA.MENU.AGENTES',
        icon: 'i-lucide-bot',
        to: accountScopedRoute('autonomia_agents_index'),
        activeOn: [
          'autonomia_agents_index',
          'autonomia_agents_builder',
          'autonomia_agent_panel',
        ],
      },
    ]);
  });

  it('com a flag ligada, não tem mais o Construtor de agentes no menu', () => {
    const [menu] = items({ journeyOn: true });
    expect(menu.children).toBeUndefined();
    expect(JSON.stringify(menu)).not.toContain('SIDEBAR.AGENTS_BUILDER');
  });
});
