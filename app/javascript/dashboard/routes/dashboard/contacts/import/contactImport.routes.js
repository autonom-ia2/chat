// Importar contatos (#1006, PRD §8.7): the journey's contact import screen. Registered by one
// line in contacts/routes.js. It needs CAMPAIGN_JOURNEY_ENABLED and CAMPAIGN_IMPORT_ENABLED
// (the validation and import jobs); with either off the menu keeps Chatwoot's own import
// dialog and this address goes back to Contacts.
import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const ContactImportPage = () => import('./ContactImportPage.vue');

export const isContactImportJourneyEnabled = () =>
  window.globalConfig?.CAMPAIGN_JOURNEY_ENABLED === 'true' &&
  window.globalConfig?.CAMPAIGN_IMPORT_ENABLED === 'true';

export const CONTACT_IMPORT_ROUTE = 'contacts_import_journey';

export const contactImportRoutes = [
  {
    path: frontendURL('accounts/:accountId/contacts/import'),
    name: CONTACT_IMPORT_ROUTE,
    component: ContactImportPage,
    // Same permission as Chatwoot's contact import (ContactPolicy#import?).
    meta: {
      featureFlag: FEATURE_FLAGS.CRM,
      permissions: ['administrator', 'contact_manage'],
    },
    beforeEnter: (to, _from, next) => {
      if (isContactImportJourneyEnabled()) {
        next();
        return;
      }
      next({ name: 'contacts_dashboard_index', params: to.params });
    },
  },
];

// "Importar contatos" in the Contacts ⋮ menu: the journey screen when it is on, otherwise
// Chatwoot's own dialog exactly as before.
export const openContactImport = (router, openChatwootDialog) =>
  isContactImportJourneyEnabled()
    ? router.push({ name: CONTACT_IMPORT_ROUTE })
    : openChatwootDialog();
