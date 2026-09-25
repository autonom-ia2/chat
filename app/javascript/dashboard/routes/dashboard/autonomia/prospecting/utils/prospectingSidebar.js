// Menu Prospecção da barra lateral: Buscar leads, Listas e o atalho
// Configurações (#682, pedido do Rodrigo), como no Orth. O atalho leva à mesma
// página de Configurações > Prospecção, que continua lá. Quem decide se o menu
// aparece é a Sidebar (admin ou permissão de prospecção, com a conta ligada);
// o atalho ainda passa pela permissão da própria rota, como a entrada de
// Configurações.
const SETTINGS_ROUTES = [
  'settings_prospecting_index',
  'autonomia_prospecting_settings',
];

export const prospectingSidebarItems = ({
  isVisible,
  t,
  accountScopedRoute,
}) => {
  if (!isVisible) return [];

  return [
    {
      name: 'Prospecting',
      label: t('SIDEBAR.PROSPECTING'),
      icon: 'i-lucide-search',
      activeOn: [
        'autonomia_prospecting_search',
        'autonomia_prospecting_lists',
        ...SETTINGS_ROUTES,
      ],
      children: [
        {
          name: 'Prospecting Search',
          label: t('SIDEBAR.PROSPECTING_SEARCH'),
          to: accountScopedRoute('autonomia_prospecting_search'),
          activeOn: ['autonomia_prospecting_search'],
        },
        {
          name: 'Prospecting Lists',
          label: t('SIDEBAR.PROSPECTING_LISTS'),
          to: accountScopedRoute('autonomia_prospecting_lists'),
          activeOn: ['autonomia_prospecting_lists'],
        },
        {
          name: 'Prospecting Settings',
          label: t('SIDEBAR.PROSPECTING_SETTINGS'),
          to: accountScopedRoute('settings_prospecting_index'),
          activeOn: SETTINGS_ROUTES,
        },
      ],
    },
  ];
};
