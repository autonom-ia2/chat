import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { INTEGRATION_MANAGE_PERMISSION } from 'dashboard/constants/permissions';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const Index = () => import('./Index.vue');
const Show = () => import('./Show.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/data'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_data_imports',
          component: Index,
          meta: {
            featureFlag: FEATURE_FLAGS.DATA_IMPORT,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
        {
          path: ':dataImportId',
          name: 'settings_data_import_show',
          component: Show,
          meta: {
            featureFlag: FEATURE_FLAGS.DATA_IMPORT,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
      ],
    },
  ],
};
