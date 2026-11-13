// Importar contatos (#1006, PRD §8.7): the journey's contact import screen. Registered by one
// line in contacts/routes.js. It needs CAMPAIGN_JOURNEY_ENABLED and CAMPAIGN_IMPORT_ENABLED
// (the validation and import jobs); with either off the menu keeps Chatwoot's own import
// dialog and this address goes back to Contacts.
//
// Trazer minha lista (#2896): on accounts with the new Relacionamentos screens, "Importar
// contatos" and "Importações" lead to that screen instead (it reads the spreadsheet and keeps
// the history of what was brought in). Without those flags everything here stays as it was.
import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { contaJaTemFlags, contaTemFlags } from 'dashboard/helper/comFlags';
import { FLAGS_DAS_TELAS_NOVAS } from 'dashboard/routes/dashboard/relacionamentos/relacionamentos.routes';

const ContactImportPage = () => import('./ContactImportPage.vue');
const ContactImportsList = () => import('./ContactImportsList.vue');

export const isContactImportJourneyEnabled = () =>
  window.globalConfig?.CAMPAIGN_JOURNEY_ENABLED === 'true' &&
  window.globalConfig?.CAMPAIGN_IMPORT_ENABLED === 'true';

export const CONTACT_IMPORT_ROUTE = 'contacts_import_journey';
// Contatos > Importações (#2771, decision 15): the contact imports, from a file or from the automation.
export const CONTACT_IMPORTS_LIST_ROUTE = 'contacts_imports_list';
const BRING_MY_LIST_ROUTE = 'relacionamentos_trazer';

// Same permission as Chatwoot's contact import (ContactPolicy#import?).
const meta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'contact_manage'],
};

// Direct link or F5: the account may not be in the store yet, so the guard loads it before
// deciding (contaTemFlags). The new screen's route asks for the same flags.
const onlyWithJourney = async (to, _from, next) => {
  if (!isContactImportJourneyEnabled()) {
    next({ name: 'contacts_dashboard_index', params: to.params });
    return;
  }
  const { accountId } = to.params;
  if (await contaTemFlags(accountId, FLAGS_DAS_TELAS_NOVAS)) {
    next({ name: BRING_MY_LIST_ROUTE, params: { accountId } });
    return;
  }
  next();
};

export const contactImportRoutes = [
  {
    // With an id, the screen opens that import where it is (the result, for one already done).
    path: frontendURL('accounts/:accountId/contacts/import/:importId?'),
    name: CONTACT_IMPORT_ROUTE,
    component: ContactImportPage,
    meta,
    beforeEnter: onlyWithJourney,
  },
  {
    path: frontendURL('accounts/:accountId/contacts/imports'),
    name: CONTACT_IMPORTS_LIST_ROUTE,
    component: ContactImportsList,
    meta,
    beforeEnter: onlyWithJourney,
  },
];

// Inside the dashboard the account is already in the store: the menu answers without waiting.
const opensBringMyList = () =>
  contaJaTemFlags(store.getters.getCurrentAccountId, FLAGS_DAS_TELAS_NOVAS);

// "Importar contatos" in the Contacts ⋮ menu: the journey screen when it is on, otherwise
// Chatwoot's own dialog exactly as before. On accounts with the new Relacionamentos the
// journey screen is Trazer minha lista.
export const openContactImport = (router, openChatwootDialog) =>
  isContactImportJourneyEnabled()
    ? router.push({
        name: opensBringMyList() ? BRING_MY_LIST_ROUTE : CONTACT_IMPORT_ROUTE,
      })
    : openChatwootDialog();

// "Importações" in the same menu (it only shows with the journey on).
export const openContactImportsList = router =>
  router.push({
    name: opensBringMyList() ? BRING_MY_LIST_ROUTE : CONTACT_IMPORTS_LIST_ROUTE,
  });
