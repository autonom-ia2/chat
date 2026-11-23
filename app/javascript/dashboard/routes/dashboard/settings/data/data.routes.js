import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { INTEGRATION_MANAGE_PERMISSION } from 'dashboard/constants/permissions';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const Index = () => import('./Index.vue');
const Show = () => import('./Show.vue');
const ExportShow = () => import('./ExportShow.vue');

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
            // Fork (upgrade 4.20.1, #3120): Data stays behind data_import and the fork permissions;
            // upstream (#16181, #16541) opens it to every account with contact_manage.
            featureFlag: FEATURE_FLAGS.DATA_IMPORT,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
            reuseOnQueryChange: true,
          },
        },
        {
          path: 'exports/:dataExportId',
          name: 'settings_data_export_show',
          component: ExportShow,
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
