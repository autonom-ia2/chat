import { FEATURE_FLAGS } from '../../../../featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { CUSTOM_ROLE_MANAGE_PERMISSION } from 'dashboard/constants/permissions.js';
import {
  ALTERAR_NOVA,
  CRIAR_NOVA,
  DUPLICAR_NOVA,
  LISTA_NOVA,
  voltarParaAtualSeDesligada,
} from './listaPelaFlag';

const FuncoesDaEquipePage = () => import('./FuncoesDaEquipePage.vue');
const FuncaoGuiadaPage = () => import('./guiada/FuncaoGuiadaPage.vue');

// Funções da equipe guiadas (#2308, épico #1784): mesmo acesso da tela de hoje (customRole.routes.js).
export const meta = {
  featureFlag: FEATURE_FLAGS.CUSTOM_ROLES,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
  permissions: ['administrator', CUSTOM_ROLE_MANAGE_PERMISSION],
};

const base = 'accounts/:accountId/settings/funcoes-da-equipe';
const rota = (caminho, name, component) => ({
  path: frontendURL(`${base}${caminho}`),
  name,
  meta,
  beforeEnter: voltarParaAtualSeDesligada,
  component,
});

export default {
  routes: [
    rota('', LISTA_NOVA, FuncoesDaEquipePage),
    // Criar, alterar e duplicar numa conversa guiada (PR 3).
    rota('/nova', CRIAR_NOVA, FuncaoGuiadaPage),
    rota('/:roleId/alterar', ALTERAR_NOVA, FuncaoGuiadaPage),
    rota('/:roleId/duplicar', DUPLICAR_NOVA, FuncaoGuiadaPage),
  ],
};
