import { FEATURE_FLAGS } from '../../../../featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { frontendURL } from 'dashboard/helper/URLHelper';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const CustomRolesHome = () => import('./Index.vue');
const CustomRoleEditor = () => import('./CustomRoleEditor.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.CUSTOM_ROLES,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
  permissions: ['administrator'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/custom-roles'),
      component: SettingsWrapper,
      // The editor holds unsaved state; a cached instance would reopen with stale data.
      props: { keepAlive: false },
      children: [
        {
          path: '',
          redirect: 'list',
        },
        {
          path: 'list',
          name: 'custom_roles_list',
          meta,
          component: CustomRolesHome,
        },
        {
          path: 'new',
          name: 'custom_roles_new',
          meta,
          component: CustomRoleEditor,
        },
        {
          path: ':roleId/edit',
          name: 'custom_roles_edit',
          meta,
          component: CustomRoleEditor,
        },
      ],
    },
  ],
};
