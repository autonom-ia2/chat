import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';

const RelationshipsHome = () => import('./RelationshipsHome.vue');
const CompanyMediaView = () => import('./CompanyMediaView.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/relationships'),
    name: 'relationships_home',
    component: RelationshipsHome,
    meta: {
      featureFlag: FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION,
      permissions: [
        'administrator',
        'agent',
        'contact_view',
        'contact_manage',
        'attribute_manage',
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/companies/:companyId/media'),
    name: 'relationships_company_media',
    component: CompanyMediaView,
    meta: {
      featureFlag: FEATURE_FLAGS.RELATIONSHIPS_COMPANY_MEDIA,
      permissions: ['administrator', 'agent'],
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
];
