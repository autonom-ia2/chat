import { frontendURL } from '../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CANNED_RESPONSE_MANAGE_PERMISSION,
  INBOX_PERMISSIONS,
  AUTOMATION_PERMISSIONS,
  SLA_MANAGE_PERMISSION,
  PEOPLE_MANAGE_PERMISSION,
  CUSTOM_ROLE_MANAGE_PERMISSION,
} from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CANNED_LIST_PERMISSIONS = [
  ...ROLES,
  ...CONVERSATION_PERMISSIONS,
  CANNED_RESPONSE_MANAGE_PERMISSION,
];

// First settings page each custom role can open (#452), in sidebar order.
const SETTINGS_LANDINGS = [
  { name: 'canned_list', permissions: CANNED_LIST_PERMISSIONS },
  { name: 'settings_inbox_list', permissions: INBOX_PERMISSIONS },
  { name: 'labels_list', permissions: ['label_manage'] },
  { name: 'attributes_list', permissions: ['attribute_manage'] },
  { name: 'automation_list', permissions: AUTOMATION_PERMISSIONS },
  { name: 'macros_wrapper', permissions: ['macro_manage'] },
  // SLA moved to CRM › SLA; settings/sla (sla_list) is not registered (#1618).
  { name: 'crm_sla_index', permissions: [SLA_MANAGE_PERMISSION] },
  // Pessoas (#1931): quem cuida das pessoas ou monta funções também chega em Configurações.
  {
    name: 'agent_list',
    permissions: [PEOPLE_MANAGE_PERMISSION],
    featureFlag: FEATURE_FLAGS.AGENT_MANAGEMENT,
  },
  {
    name: 'custom_roles_list',
    permissions: [CUSTOM_ROLE_MANAGE_PERMISSION],
    featureFlag: FEATURE_FLAGS.CUSTOM_ROLES,
  },
];

import account from './account/account.routes';
import agent from './agents/agent.routes';
import assignmentPolicy from './assignmentPolicy/assignmentPolicy.routes';
import agentBot from './agentBots/agentBot.routes';
import attributes from './attributes/attributes.routes';
import automation from './automation/automation.routes';
import auditlogs from './auditlogs/audit.routes';
import billing from './billing/billing.routes';
import canned from './canned/canned.routes';
import inbox from './inbox/inbox.routes';
import templates from './templates/templates.routes';
import integrations from './integrations/integrations.routes';
import labels from './labels/labels.routes';
import macros from './macros/macros.routes';
import reports from './reports/reports.routes';
import teams from './teams/teams.routes';
import customRoles from './customRoles/customRole.routes';
import funcoesDaEquipe from './funcoesDaEquipe/funcoesDaEquipe.routes';
import profile from './profile/profile.routes';
import security from './security/security.routes';
import conversationWorkflow from './conversationWorkflow/conversationWorkflow.routes';
import captain from './captain/captain.routes';
import prospecting from './prospecting/prospecting.routes';
import booking from './booking/booking.routes';
import data from './data/data.routes';
import {
  routes as inicioRoutes,
  CHAVES_EXTRAS_DO_INICIO,
} from './inicio/inicio.routes';
import { destinoDeConfiguracoes } from './inicio/destinoDeConfiguracoes';

const SettingsWrapper = () => import('./SettingsWrapper.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings'),
      name: 'settings_home',
      meta: {
        permissions: [
          ...SETTINGS_LANDINGS.flatMap(page => page.permissions),
          ...CHAVES_EXTRAS_DO_INICIO,
        ],
      },
      // Nunca é exibida: o beforeEnter sempre manda para outra tela.
      component: SettingsWrapper,
      beforeEnter: to => destinoDeConfiguracoes(to, SETTINGS_LANDINGS),
    },
    ...account.routes,
    ...agent.routes,
    ...assignmentPolicy.routes,
    ...agentBot.routes,
    ...attributes.routes,
    ...automation.routes,
    ...auditlogs.routes,
    ...billing.routes,
    ...canned.routes,
    ...inbox.routes,
    ...templates.routes,
    ...integrations.routes,
    ...data.routes,
    ...labels.routes,
    ...macros.routes,
    ...reports.routes,
    ...teams.routes,
    ...customRoles.routes,
    ...funcoesDaEquipe.routes,
    ...profile.routes,
    ...security.routes,
    ...conversationWorkflow.routes,
    ...captain.routes,
    ...prospecting.routes,
    ...booking.routes,
    ...inicioRoutes,
  ],
};
