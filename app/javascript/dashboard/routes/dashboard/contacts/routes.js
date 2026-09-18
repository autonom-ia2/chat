import { frontendURL } from '../../../helper/URLHelper';
import ContactsIndex from './pages/ContactsIndex.vue';
import ContactManageView from './pages/ContactManageView.vue';
import CampaignImportHistory from './pages/CampaignImportHistory.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';
import { CAMPAIGN_PERMISSIONS } from 'dashboard/constants/permissions.js';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent', 'contact_manage', 'contact_view'],
};

const campaignImportMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contacts/campaign-imports'),
    name: 'contacts_campaign_imports',
    component: CampaignImportHistory,
    meta: campaignImportMeta,
    beforeEnter: (_to, _from, next) => {
      if (window.globalConfig?.CAMPAIGN_IMPORT_ENABLED === 'true') {
        next();
        return;
      }
      next({ name: 'contacts_dashboard_index' });
    },
  },
  {
    path: frontendURL('accounts/:accountId/contacts'),
    component: ContactsIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_dashboard_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_dashboard_segments_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_dashboard_labels_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'active',
        name: 'contacts_dashboard_active',
        component: ContactsIndex,
        meta: commonMeta,
      },
    ],
  },
  {
    path: frontendURL('accounts/:accountId/contacts/:contactId'),
    component: ContactManageView,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_edit',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_edit_segment',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_edit_label',
        component: ContactManageView,
        meta: commonMeta,
      },
    ],
  },
];
