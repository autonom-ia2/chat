import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const Index = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/labels'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'labels_wrapper',
          meta: {
            permissions: ['administrator', 'label_manage'],
          },
          redirect: to => {
            return { name: 'labels_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'labels_list',
          meta: {
            featureFlag: FEATURE_FLAGS.LABELS,
            permissions: ['administrator', 'label_manage'],
          },
          component: Index,
        },
      ],
    },
  ],
};
