import { createRouter, createMemoryHistory } from 'vue-router';

const vazio = { render: () => null };
vi.mock('../ContactImportPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/ContactsIndex.vue', () => ({ default: vazio }));
vi.mock('../../pages/ContactManageView.vue', () => ({ default: vazio }));
vi.mock('../../pages/CampaignImportHistory.vue', () => ({ default: vazio }));

const { routes } = await import('../../routes');
const { openContactImport, CONTACT_IMPORT_ROUTE } = await import(
  '../contactImport.routes'
);

const navigate = async () => {
  const router = createRouter({ history: createMemoryHistory(), routes });
  await router.push({ name: CONTACT_IMPORT_ROUTE, params: { accountId: 1 } });
  return router.currentRoute.value;
};

const ON = {
  CAMPAIGN_JOURNEY_ENABLED: 'true',
  CAMPAIGN_IMPORT_ENABLED: 'true',
};

describe(
  'Importar contatos route (#1006, PRD §8.7, A5 style)',
  { timeout: 20000 },
  () => {
    afterEach(() => {
      window.globalConfig = {};
    });

    it('flags on: opens the journey screen with the contact import permission', async () => {
      window.globalConfig = ON;
      const route = await navigate();

      expect(route.name).toBe(CONTACT_IMPORT_ROUTE);
      expect(route.path).toBe('/app/accounts/1/contacts/import');
      expect(route.meta.permissions).toEqual([
        'administrator',
        'contact_manage',
      ]);
    });

    it.each([
      { CAMPAIGN_JOURNEY_ENABLED: 'false', CAMPAIGN_IMPORT_ENABLED: 'true' },
      { CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'false' },
      {},
    ])('flag off (%o): goes back to Contacts', async config => {
      window.globalConfig = config;
      const route = await navigate();

      expect(route.name).toBe('contacts_dashboard_index');
    });

    it('menu: flags off keep the Chatwoot dialog exactly as before', () => {
      window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'false' };
      const router = { push: vi.fn() };
      const openDialog = vi.fn();

      openContactImport(router, openDialog);

      expect(openDialog).toHaveBeenCalledTimes(1);
      expect(router.push).not.toHaveBeenCalled();
    });

    it('menu: flags on open the journey screen instead of the dialog', () => {
      window.globalConfig = ON;
      const router = { push: vi.fn() };
      const openDialog = vi.fn();

      openContactImport(router, openDialog);

      expect(router.push).toHaveBeenCalledWith({ name: CONTACT_IMPORT_ROUTE });
      expect(openDialog).not.toHaveBeenCalled();
    });
  }
);
