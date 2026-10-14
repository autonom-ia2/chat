// Menu Agentes da barra lateral. Quem decide se ele aparece é a Sidebar (ENV
// master, conta ligada e admin ou permissão autonomia_*). Com a nova jornada
// (#1181, flag autonomia_agents_journey) vira um item só, "Agentes": criar
// agente fica como botão na lista. Sem a flag, o item é o mesmo de antes.
const AGENTS_ROUTES = [
  'autonomia_agents_index',
  'autonomia_agents_builder',
  'autonomia_agent_panel',
];

const journeyItem = ({ t, accountScopedRoute }) => ({
  name: 'Agents',
  label: t('AGENTS.JORNADA.MENU.AGENTES'),
  icon: 'i-lucide-bot',
  to: accountScopedRoute('autonomia_agents_index'),
  activeOn: [...AGENTS_ROUTES],
});

const legacyItem = ({ t, accountScopedRoute }) => ({
  name: 'Agents',
  label: t('SIDEBAR.AGENTS_AUTONOMIA'),
  icon: 'i-lucide-bot',
  activeOn: [...AGENTS_ROUTES],
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
});

export const agentsSidebarItems = ({
  isVisible,
  journeyOn,
  t,
  accountScopedRoute,
}) => {
  if (!isVisible) return [];

  const build = journeyOn ? journeyItem : legacyItem;
  return [build({ t, accountScopedRoute })];
};
