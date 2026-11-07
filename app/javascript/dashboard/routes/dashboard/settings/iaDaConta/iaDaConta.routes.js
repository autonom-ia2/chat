import { frontendURL } from 'dashboard/helper/URLHelper';

const IaDaContaPage = () => import('./IaDaContaPage.vue');

// #2472: só o administrador. Chave e login de IA são credencial da conta e
// nunca se delegam por função personalizada.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ia-da-conta'),
      name: 'settings_ia_da_conta',
      meta: { permissions: ['administrator'] },
      component: IaDaContaPage,
    },
  ],
};
