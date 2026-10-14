import { frontendURL } from 'dashboard/helper/URLHelper.js';

const SubscriptionPage = () => import('./pages/SubscriptionPage.vue');
const InvoicesPage = () => import('./pages/InvoicesPage.vue');
const StoreCatalogPage = () => import('./pages/StoreCatalogPage.vue');

const adminMeta = {
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/financial/store'),
    name: 'autonomia_financial_store',
    meta: { superAdminOnly: true, permissions: ['administrator', 'agent'] },
    component: StoreCatalogPage,
  },
  {
    path: frontendURL('accounts/:accountId/financial/subscription'),
    name: 'autonomia_financial_subscription',
    meta: adminMeta,
    component: SubscriptionPage,
  },
  {
    path: frontendURL('accounts/:accountId/financial/invoices'),
    name: 'autonomia_financial_invoices',
    meta: adminMeta,
    component: InvoicesPage,
  },
];

export default { routes };
