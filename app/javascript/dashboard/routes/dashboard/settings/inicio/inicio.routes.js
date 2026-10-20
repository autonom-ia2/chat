import { frontendURL } from '../../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CANNED_RESPONSE_MANAGE_PERMISSION,
  INBOX_PERMISSIONS,
  AUTOMATION_PERMISSIONS,
  CRM_MANAGE_AI_PERMISSION,
  CRM_ADMIN_PERMISSION,
  PEOPLE_MANAGE_PERMISSION,
  CUSTOM_ROLE_MANAGE_PERMISSION,
} from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const SettingsInicioPage = () => import('./SettingsInicioPage.vue');

// Chaves que abrem a página de cartões além das telas de Configurações de sempre: quem cuida da IA do CRM vê o
// cartão da passagem. O settings_home (/settings) aceita as mesmas, para o endereço digitado chegar aqui.
export const CHAVES_EXTRAS_DO_INICIO = [
  CRM_MANAGE_AI_PERMISSION,
  CRM_ADMIN_PERMISSION,
];

// Página inicial de Configurações em cartões (#1617), só com o menu novo ligado na conta. Quem abre: quem já
// abria alguma tela de Configurações (as chaves do `settings_home`, mais crm_manage_ai/crm_admin, que dão o
// cartão da passagem); cada cartão confere a própria rota. Flag desligada: a página manda para `settings_home`.
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
        PEOPLE_MANAGE_PERMISSION,
        CUSTOM_ROLE_MANAGE_PERMISSION,
        // Quem cuida da IA do CRM chega na passagem pelo cartão "Passar para uma pessoa".
        ...CHAVES_EXTRAS_DO_INICIO,
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
