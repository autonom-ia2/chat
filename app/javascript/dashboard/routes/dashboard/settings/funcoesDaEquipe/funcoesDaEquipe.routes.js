import { FEATURE_FLAGS } from '../../../../featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { CUSTOM_ROLE_MANAGE_PERMISSION } from 'dashboard/constants/permissions.js';
import { LISTA_NOVA, voltarParaListaAtualSeDesligada } from './listaPelaFlag';

const FuncoesDaEquipePage = () => import('./FuncoesDaEquipePage.vue');

// Funções da equipe guiadas (#2308, épico #1784): mesmo acesso da tela de hoje (customRole.routes.js).
// Os próximos PRs acrescentam funcoes_equipe_new, funcoes_equipe_edit e funcoes_equipe_duplicate aqui.
export const meta = {
  featureFlag: FEATURE_FLAGS.CUSTOM_ROLES,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
  permissions: ['administrator', CUSTOM_ROLE_MANAGE_PERMISSION],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/funcoes-da-equipe'),
      name: LISTA_NOVA,
      meta,
      beforeEnter: voltarParaListaAtualSeDesligada,
      component: FuncoesDaEquipePage,
    },
  ],
};
