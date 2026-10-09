import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { CRM_MANAGE_AI_PERMISSION } from 'dashboard/constants/permissions';
import SettingsWrapper from '../SettingsWrapper.vue';
import AssignmentPolicyIndex from './Index.vue';
import AgentAssignmentIndex from './pages/AgentAssignmentIndexPage.vue';
import AgentAssignmentCreate from './pages/AgentAssignmentCreatePage.vue';
import AgentAssignmentEdit from './pages/AgentAssignmentEditPage.vue';
import AgentCapacityIndex from './pages/AgentCapacityIndexPage.vue';
import AgentCapacityCreate from './pages/AgentCapacityCreatePage.vue';
import AgentCapacityEdit from './pages/AgentCapacityEditPage.vue';
import CrmHandoffIndex from './pages/CrmHandoffIndexPage.vue';
import CrmHandoffEdit from './pages/CrmHandoffEditPage.vue';

// Mirrors ensureCrmAiEnabled from crm.routes.js: the handoff pages only make
// sense when the CRM kanban + CRM AI are enabled on this installation.
const ensureCrmAiEnabled = (to, _from, next) => {
  if (
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
    window.globalConfig?.CRM_AI_ENABLED === 'true'
  ) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/assignment-policy'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'assignment_policy_index', params: to.params };
          },
        },
        {
          path: 'index',
          name: 'assignment_policy_index',
          component: AssignmentPolicyIndex,
          meta: {
            featureFlag: FEATURE_FLAGS.ASSIGNMENT_V2,
            permissions: ['administrator'],
          },
        },
        {
          path: 'assignment',
          name: 'agent_assignment_policy_index',
          component: AgentAssignmentIndex,
          meta: {
            featureFlag: FEATURE_FLAGS.ASSIGNMENT_V2,
            permissions: ['administrator'],
          },
        },
        {
          path: 'assignment/create',
          name: 'agent_assignment_policy_create',
          component: AgentAssignmentCreate,
          meta: {
            featureFlag: FEATURE_FLAGS.ASSIGNMENT_V2,
            permissions: ['administrator'],
          },
        },
        {
          path: 'assignment/edit/:id',
          name: 'agent_assignment_policy_edit',
          component: AgentAssignmentEdit,
          meta: {
            featureFlag: FEATURE_FLAGS.ASSIGNMENT_V2,
            permissions: ['administrator'],
          },
        },
        {
          path: 'handoff',
          name: 'crm_handoff_settings_index',
          component: CrmHandoffIndex,
          beforeEnter: ensureCrmAiEnabled,
          meta: {
            featureFlag: FEATURE_FLAGS.CRM,
            permissions: ['administrator', CRM_MANAGE_AI_PERMISSION],
          },
        },
        {
          path: 'handoff/:pipelineId',
          name: 'crm_handoff_settings_edit',
          component: CrmHandoffEdit,
          beforeEnter: ensureCrmAiEnabled,
          meta: {
            featureFlag: FEATURE_FLAGS.CRM,
            permissions: ['administrator', CRM_MANAGE_AI_PERMISSION],
          },
        },
        {
          path: 'capacity',
          name: 'agent_capacity_policy_index',
          component: AgentCapacityIndex,
          meta: {
            featureFlag: FEATURE_FLAGS.ADVANCED_ASSIGNMENT,
            permissions: ['administrator'],
          },
        },
        {
          path: 'capacity/create',
          name: 'agent_capacity_policy_create',
          component: AgentCapacityCreate,
          meta: {
            featureFlag: FEATURE_FLAGS.ADVANCED_ASSIGNMENT,
            permissions: ['administrator'],
          },
        },
        {
          path: 'capacity/edit/:id',
          name: 'agent_capacity_policy_edit',
          component: AgentCapacityEdit,
          meta: {
            featureFlag: FEATURE_FLAGS.ADVANCED_ASSIGNMENT,
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
