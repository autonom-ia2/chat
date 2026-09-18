import { frontendURL } from '../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CANNED_RESPONSE_MANAGE_PERMISSION,
  INBOX_PERMISSIONS,
  AUTOMATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper.js';

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
  { name: 'sla_list', permissions: ['sla_manage'] },
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
import store from '../../../store';
import teams from './teams/teams.routes';
import customRoles from './customRoles/customRole.routes';
import profile from './profile/profile.routes';
import security from './security/security.routes';
import conversationWorkflow from './conversationWorkflow/conversationWorkflow.routes';
import captain from './captain/captain.routes';
import prospecting from './prospecting/prospecting.routes';
import data from './data/data.routes';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings'),
      name: 'settings_home',
      meta: {
        permissions: SETTINGS_LANDINGS.flatMap(page => page.permissions),
      },
      redirect: to => {
        if (
          store.getters.getCurrentRole === 'administrator' &&
          store.getters.getCurrentCustomRoleId === null
        ) {
          return { name: 'general_settings_index', params: to.params };
        }

        const permissions = getUserPermissions(
          store.getters.getCurrentUser,
          to.params.accountId
        );
        const landing = SETTINGS_LANDINGS.find(page =>
          hasPermissions(page.permissions, permissions)
        );
        return { name: landing.name, params: to.params };
      },
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
    ...profile.routes,
    ...security.routes,
    ...conversationWorkflow.routes,
    ...captain.routes,
    ...prospecting.routes,
  ],
};
