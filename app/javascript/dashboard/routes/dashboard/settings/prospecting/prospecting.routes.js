import { frontendURL } from '../../../../helper/URLHelper';
// Mesmo guarda assíncrono das rotas da Prospecção: espera a conta no F5 (#1618).
import { ensureProspectingEnabled } from '../../autonomia/contaDaRota';

const SettingsWrapper = () => import('../SettingsWrapper.vue');

const ProspectingSettingsPage = () =>
  import('../../autonomia/prospecting/pages/ProspectingSettingsPage.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/prospecting'),
      meta: {
        permissions: ['administrator', 'prospecting_manage'],
      },
      beforeEnter: ensureProspectingEnabled,
      component: SettingsWrapper,
      props: {
        headerTitle: 'PROSPECTING.SETTINGS.TITLE',
        icon: 'i-lucide-search',
      },
      children: [
        {
          path: '',
          name: 'settings_prospecting_index',
          component: ProspectingSettingsPage,
          meta: {
            permissions: ['administrator', 'prospecting_manage'],
          },
        },
      ],
    },
  ],
};
