// "Trazer meu modelo" (#1099): com a flag email_template_import desligada, o endereço direto da tela
// também fecha — meta.featureFlag só esconde o menu. Com link direto ou F5, o guarda espera a conta
// chegar à store antes de decidir.
import campaignsRoutes from '../campaigns.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));

const findRoute = (routes, name) =>
  routes.reduce(
    (found, route) =>
      found ||
      (route.name === name ? route : findRoute(route.children || [], name)),
    null
  );

const importRoute = findRoute(
  campaignsRoutes.routes,
  'campaigns_email_template_import'
);

const enter = async () => {
  const next = vi.fn();
  await importRoute.beforeEnter({ params: { accountId: '9' } }, {}, next);
  return next;
};

// The store starts without the account (direct link) and has it only after accounts/get.
const accountArrivesLater = account => {
  let loaded = {};
  store.getters['accounts/getAccount'] = () => loaded;
  store.dispatch.mockImplementation(async () => {
    loaded = account;
  });
};

const library = {
  name: 'campaigns_email_templates',
  params: { accountId: '9' },
};

describe('the "Trazer meu modelo" address', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    window.globalConfig = {
      EMAIL_CAMPAIGN_ENABLED: 'true',
      CRM_KANBAN_ENABLED: 'true',
    };
  });

  it('opens when the account has the flag, waiting for the account to load', async () => {
    accountArrivesLater({ id: 9, features: { email_template_import: true } });
    const next = await enter();

    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  it('goes back to the library when the flag is off', async () => {
    accountArrivesLater({ id: 9, features: { email_template_import: false } });
    expect(await enter()).toHaveBeenCalledWith(library);
  });

  it('does not fetch the account again when the store already has it', async () => {
    store.getters['accounts/getAccount'] = () => ({ id: 9, features: {} });
    const next = await enter();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith(library);
  });

  it('goes back to the library when the account does not load', async () => {
    store.getters['accounts/getAccount'] = () => ({});
    store.dispatch.mockRejectedValue(new Error('rede'));
    expect(await enter()).toHaveBeenCalledWith(library);
  });

  it('keeps the e-mail campaigns gate in front of it', async () => {
    window.globalConfig = { EMAIL_CAMPAIGN_ENABLED: 'false' };
    const next = await enter();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith({
      name: 'campaigns_sms_index',
      params: { accountId: '9' },
    });
  });
});
