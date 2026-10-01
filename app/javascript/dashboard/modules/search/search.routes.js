import { frontendURL } from '../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CONTACT_PERMISSIONS,
  PORTAL_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

const SearchView = () => import('./components/SearchView.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/search/:tab?'),
    name: 'search',
    meta: {
      permissions: [
        ...ROLES,
        ...CONVERSATION_PERMISSIONS,
        CONTACT_PERMISSIONS,
        PORTAL_PERMISSIONS,
      ],
    },
    component: SearchView,
  },
];
