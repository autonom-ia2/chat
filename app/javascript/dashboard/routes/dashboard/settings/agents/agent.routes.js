import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { PEOPLE_MANAGE_PERMISSION } from 'dashboard/constants/permissions.js';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const AgentHome = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/agents'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'agent_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'agent_list',
          component: AgentHome,
          meta: {
            featureFlag: FEATURE_FLAGS.AGENT_MANAGEMENT,
            permissions: ['administrator', PEOPLE_MANAGE_PERMISSION],
          },
        },
      ],
    },
  ],
};
