import { frontendURL } from '../../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CANNED_RESPONSE_MANAGE_PERMISSION,
  INBOX_PERMISSIONS,
  AUTOMATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const SettingsInicioPage = () => import('./SettingsInicioPage.vue');

// Página inicial de Configurações em cartões (#1617), só com o menu novo ligado na conta. Quem abre: quem já
// abria alguma tela de Configurações (as mesmas chaves do `settings_home`); cada cartão confere a própria rota.
export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/inicio'),
    name: 'settings_inicio',
    component: SettingsInicioPage,
    meta: {
      featureFlag: FEATURE_FLAGS.MENU_LATERAL_NOVO,
      permissions: [
        ...ROLES,
        ...CONVERSATION_PERMISSIONS,
        CANNED_RESPONSE_MANAGE_PERMISSION,
        ...INBOX_PERMISSIONS,
        'label_manage',
        'attribute_manage',
        'macro_manage',
        ...AUTOMATION_PERMISSIONS,
        'sla_manage',
      ],
    },
  },
];

// `settings_home` cai aqui quando o menu novo está ligado na conta (#1617).
export const menuNovoLigado = (store, accountId) =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    Number(accountId),
    FEATURE_FLAGS.MENU_LATERAL_NOVO
  );
