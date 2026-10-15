import { createRouter, createMemoryHistory } from 'vue-router';
import { frontendURL } from '../URLHelper';
import { defaultRedirectPage, validateLoggedInRoutes } from '../routeHelpers';
import conversationRoutes from '../../routes/dashboard/conversation/conversation.routes';
import { routes as crmRoutes } from '../../routes/dashboard/crm/crm.routes';
import { routes as contactRoutes } from '../../routes/dashboard/contacts/routes';
import campaignRoutes from '../../routes/dashboard/campaigns/campaigns.routes';
import reportRoutes from '../../routes/dashboard/settings/reports/reports.routes';
import helpcenterRoutes from '../../routes/dashboard/helpcenter/helpcenter.routes';
import profileRoutes from '../../routes/dashboard/settings/profile/profile.routes';

// #1643: someone who may not open a screen is sent to the first screen they CAN
// open — never to the dashboard when the dashboard is closed to them too.

const Blank = { render: () => null };
const stripComponents = routes =>
  routes.map(({ component, children, ...rest }) => ({
    ...rest,
    component: Blank,
    ...(children ? { children: stripComponents(children) } : {}),
  }));

// The real route table of every landing page (meta.permissions as shipped),
// without components, plus one screen nobody but the
// administrator opens.
const buildRouter = user => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      ...stripComponents([
        ...conversationRoutes.routes,
        ...crmRoutes,
        ...contactRoutes,
        ...campaignRoutes.routes,
        ...reportRoutes.routes,
        ...helpcenterRoutes.routes,
        ...profileRoutes.routes,
      ]),
      {
        path: frontendURL('accounts/:accountId/settings/billing-test'),
        name: 'admin_only_test',
        meta: { permissions: ['administrator'] },
        component: Blank,
      },
    ],
  });
  router.beforeEach((to, _from, next) => {
    const nextRoute = validateLoggedInRoutes(to, user);
    return nextRoute ? next(frontendURL(nextRoute)) : next();
  });
  return router;
};

const userWith = (permissions, role = 'agent') => ({
  accounts: [{ id: 2, status: 'active', role, permissions }],
});

const open = async (router, path) => {
  await router.push(frontendURL(`accounts/2/${path}`));
  return router.currentRoute.value.path;
};

describe('landing page for someone without access (#1643)', () => {
  const originalConfig = window.globalConfig;

  beforeEach(() => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  });

  afterEach(() => {
    window.globalConfig = originalConfig;
  });

  it('opens the CRM for a CRM-only custom role entering the account', async () => {
    const router = buildRouter(userWith(['crm_view', 'custom_role']));
    expect(await open(router, 'dashboard')).toBe('/app/accounts/2/crm');
  });

  it('opens the CRM for a CRM-only custom role on a forbidden screen', async () => {
    const router = buildRouter(userWith(['crm_view', 'custom_role']));
    expect(await open(router, 'settings/billing-test')).toBe(
      '/app/accounts/2/crm'
    );
  });

  it('skips the CRM when it is turned off and opens the profile', async () => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'false' };
    const router = buildRouter(userWith(['crm_view', 'custom_role']));
    expect(await open(router, 'dashboard')).toBe(
      '/app/accounts/2/profile/settings'
    );
  });

  it('opens campaigns for a campaigns-only custom role', async () => {
    const router = buildRouter(userWith(['campaign_view', 'custom_role']));
    expect(await open(router, 'dashboard')).toMatch(
      /^\/app\/accounts\/2\/campaigns\//
    );
  });

  it('opens the profile for a custom role with no landing page', async () => {
    const router = buildRouter(userWith(['label_manage', 'custom_role']));
    expect(await open(router, 'dashboard')).toBe(
      '/app/accounts/2/profile/settings'
    );
  });

  it('keeps the administrator on the dashboard', async () => {
    const router = buildRouter(userWith(['administrator'], 'administrator'));
    expect(await open(router, 'dashboard')).toBe('/app/accounts/2/dashboard');
  });

  it('keeps sending a plain agent from a forbidden screen to the dashboard', async () => {
    const router = buildRouter(userWith(['agent']));
    expect(await open(router, 'settings/billing-test')).toBe(
      '/app/accounts/2/dashboard'
    );
  });

  // Every landing page must open for whoever it is chosen for: open each
  // choice through the real routes and check the guard lets it stay.
  it.each([
    [['administrator']],
    [['agent']],
    [['conversation_participating_manage', 'custom_role']],
    [['contact_view', 'custom_role']],
    [['crm_view', 'custom_role']],
    [['campaign_manage', 'custom_role']],
    [['report_manage', 'custom_role']],
    [['knowledge_base_manage', 'custom_role']],
    [['custom_role']],
  ])('lands %j on a screen it can open', async permissions => {
    const user = userWith(permissions);
    const router = buildRouter(user);
    const target = defaultRedirectPage(
      { params: { accountId: 2 } },
      permissions
    );
    const landed = await open(router, target.replace('accounts/2/', ''));
    expect(landed.startsWith(frontendURL(target))).toBe(true);
    expect(validateLoggedInRoutes(router.currentRoute.value, user)).toBeNull();
  });
});
