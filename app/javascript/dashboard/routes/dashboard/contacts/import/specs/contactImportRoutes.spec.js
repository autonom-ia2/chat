import { createRouter, createMemoryHistory } from 'vue-router';
import store from 'dashboard/store';

const vazio = { render: () => null };
vi.mock('../ContactImportPage.vue', () => ({ default: vazio }));
vi.mock('../ContactImportsList.vue', () => ({ default: vazio }));
vi.mock('../../pages/ContactsIndex.vue', () => ({ default: vazio }));
vi.mock('../../pages/ContactManageView.vue', () => ({ default: vazio }));
vi.mock('../../pages/CampaignImportHistory.vue', () => ({ default: vazio }));
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

const { routes } = await import('../../routes');
const {
  openContactImport,
  openContactImportsList,
  CONTACT_IMPORT_ROUTE,
  CONTACT_IMPORTS_LIST_ROUTE,
} = await import('../contactImport.routes');

// Trazer minha lista (#2896): the screen that replaces these two on accounts with the new
// Relacionamentos. The router here only needs to know the route exists.
const BRING_MY_LIST = 'relacionamentos_trazer';
const bringMyListRoute = {
  path: '/app/accounts/:accountId/relacionamentos/trazer',
  name: BRING_MY_LIST,
  component: vazio,
};

const navigate = async (name = CONTACT_IMPORT_ROUTE, params = {}) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [...routes, bringMyListRoute],
  });
  await router.push({ name, params: { accountId: 1, ...params } });
  return router.currentRoute.value;
};

const ON = {
  CAMPAIGN_JOURNEY_ENABLED: 'true',
  CAMPAIGN_IMPORT_ENABLED: 'true',
};

// The flags the new screen's own route asks for (relacionamentos.routes.js).
const NEW_RELATIONSHIPS = ['relacionamentos_novo', 'relationships_navigation'];
const accountWith = (flags, account = { id: 1 }) => {
  store.getters['accounts/getAccount'] = () => account;
  store.getters['accounts/isFeatureEnabledonAccount'] = (_id, flag) =>
    flags.includes(flag);
  store.getters.getCurrentAccountId = 1;
};

describe(
  'Importar contatos route (#1006, PRD §8.7, A5 style)',
  { timeout: 20000 },
  () => {
    beforeEach(() => {
      store.dispatch.mockReset();
      accountWith([]);
    });

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

    // Contatos > Importações (#2771): the list, and an import opened by id, with the same permission.
    it('flags on: opens the imports list and an import by id', async () => {
      window.globalConfig = ON;
      const list = await navigate(CONTACT_IMPORTS_LIST_ROUTE);
      const byId = await navigate(CONTACT_IMPORT_ROUTE, { importId: 42 });

      expect(list.name).toBe(CONTACT_IMPORTS_LIST_ROUTE);
      expect(list.path).toBe('/app/accounts/1/contacts/imports');
      expect(list.meta.permissions).toEqual([
        'administrator',
        'contact_manage',
      ]);
      expect(byId.path).toBe('/app/accounts/1/contacts/import/42');
      expect(byId.params.importId).toBe('42');
    });

    it('flag off: the imports list goes back to Contacts', async () => {
      window.globalConfig = {};
      const route = await navigate(CONTACT_IMPORTS_LIST_ROUTE);

      expect(route.name).toBe('contacts_dashboard_index');
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

    it('menu: "Importações" opens the imports list', () => {
      window.globalConfig = ON;
      const router = { push: vi.fn() };

      openContactImportsList(router);

      expect(router.push).toHaveBeenCalledWith({
        name: CONTACT_IMPORTS_LIST_ROUTE,
      });
    });

    // Trazer minha lista (#2896): with the new Relacionamentos on, the two old entries lead to it.
    describe('account with the new Relacionamentos', () => {
      beforeEach(() => {
        window.globalConfig = ON;
        accountWith(NEW_RELATIONSHIPS);
      });

      it.each([
        ['the import screen', CONTACT_IMPORT_ROUTE, {}],
        ['an import opened by id', CONTACT_IMPORT_ROUTE, { importId: 42 }],
        ['the imports list', CONTACT_IMPORTS_LIST_ROUTE, {}],
      ])('%s goes to Trazer minha lista', async (_what, name, params) => {
        const route = await navigate(name, params);

        expect(route.name).toBe(BRING_MY_LIST);
        expect(route.path).toBe('/app/accounts/1/relacionamentos/trazer');
        expect(route.params).toEqual({ accountId: '1' });
      });

      it('direct link (account not loaded yet): loads the account before deciding', async () => {
        accountWith(NEW_RELATIONSHIPS, null);
        store.dispatch.mockImplementation(async () => {
          store.getters['accounts/getAccount'] = () => ({ id: 1 });
        });

        const route = await navigate();

        expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
        expect(route.name).toBe(BRING_MY_LIST);
      });

      it('menu: "Importar contatos" and "Importações" open Trazer minha lista', () => {
        const router = { push: vi.fn() };
        const openDialog = vi.fn();

        openContactImport(router, openDialog);
        openContactImportsList(router);

        expect(router.push.mock.calls).toEqual([
          [{ name: BRING_MY_LIST }],
          [{ name: BRING_MY_LIST }],
        ]);
        expect(openDialog).not.toHaveBeenCalled();
      });

      it('journey off: everything stays as before (the new screen needs the import jobs too)', async () => {
        window.globalConfig = {};
        const router = { push: vi.fn() };
        const openDialog = vi.fn();

        openContactImport(router, openDialog);
        const route = await navigate();

        expect(openDialog).toHaveBeenCalledTimes(1);
        expect(router.push).not.toHaveBeenCalled();
        expect(route.name).toBe('contacts_dashboard_index');
      });
    });

    it.each([[['relacionamentos_novo']], [['relationships_navigation']]])(
      'account with only %o: stays on the old screens (the new one would not open)',
      async flags => {
        window.globalConfig = ON;
        accountWith(flags);
        const router = { push: vi.fn() };

        openContactImport(router, vi.fn());
        const route = await navigate();
        const list = await navigate(CONTACT_IMPORTS_LIST_ROUTE);

        expect(router.push).toHaveBeenCalledWith({
          name: CONTACT_IMPORT_ROUTE,
        });
        expect(route.name).toBe(CONTACT_IMPORT_ROUTE);
        expect(list.name).toBe(CONTACT_IMPORTS_LIST_ROUTE);
      }
    );

    it('account that fails to load: stays on the old screen', async () => {
      window.globalConfig = ON;
      accountWith(NEW_RELATIONSHIPS, null);
      store.dispatch.mockRejectedValue(new Error('offline'));

      const route = await navigate();

      expect(route.name).toBe(CONTACT_IMPORT_ROUTE);
    });
  }
);
