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

// #2692 — com a flag prospeccao_nova (protótipo), o menu abre as telas novas:
// "Achar empresas" (só quem busca), "Suas buscas" e "Para chamar" (a fila).
// Configurações saem do menu lateral e continuam em Configurações da conta.
const ACHAR_ROUTES = [
  'autonomia_prospecting_achar',
  'autonomia_prospecting_achar_buscas',
  'autonomia_prospecting_achar_busca',
  'autonomia_prospecting_para_chamar',
];

const acharItems = ({ podeBuscar, t, accountScopedRoute }) => [
  {
    name: 'Prospecting',
    label: t('SIDEBAR.PROSPECTING'),
    icon: 'i-lucide-search',
    activeOn: ACHAR_ROUTES,
    // Fase 1: só 2 filhos. "Para chamar" (fase 5) abre pela URL e não entra
    // no menu (decisão da rodada 3).
    children: [
      ...(podeBuscar
        ? [
            {
              name: 'Prospecting Achar',
              label: t('PROSPECTING_ACHAR.MENU.ACHAR'),
              to: accountScopedRoute('autonomia_prospecting_achar'),
              activeOn: ['autonomia_prospecting_achar'],
            },
          ]
        : []),
      {
        name: 'Prospecting Buscas',
        label: t('PROSPECTING_ACHAR.MENU.BUSCAS'),
        to: accountScopedRoute('autonomia_prospecting_achar_buscas'),
        activeOn: [
          'autonomia_prospecting_achar_buscas',
          'autonomia_prospecting_achar_busca',
        ],
      },
    ],
  },
];

export const prospectingSidebarItems = ({
  isVisible,
  t,
  accountScopedRoute,
  novaOn = false,
  podeBuscar = false,
}) => {
  if (!isVisible) return [];
  if (novaOn) return acharItems({ podeBuscar, t, accountScopedRoute });

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
