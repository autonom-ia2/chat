import {
  hasPermissions,
  getUserPermissions,
  getCurrentAccount,
} from './permissionsHelper';

import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CONVERSATION_VIEW_PERMISSION,
  CONTACT_PERMISSIONS,
  CONTACT_VIEW_PERMISSION,
  REPORTS_PERMISSIONS,
  PORTAL_PERMISSIONS,
  CRM_VIEW_PERMISSION,
  CAMPAIGN_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

export const routeIsAccessibleFor = (route, userPermissions = []) => {
  const { meta: { permissions: routePermissions = [] } = {} } = route;
  return hasPermissions(routePermissions, userPermissions);
};

// The CRM screens send everyone back to the dashboard while the CRM is off (crm.routes.js).
export const isCrmKanbanEnabled = () =>
  window.globalConfig?.CRM_KANBAN_ENABLED === 'true';

// Where someone lands when the screen they asked for is not theirs (#1643).
// The first page the person can open wins, in this order: conversations (every
// administrator and agent stops here, as before), contacts, CRM, campaigns,
// reports, help center. Each entry's permissions must open the destination
// route's meta.permissions — routeHelpersLanding.spec.js checks it against the real routes.
const LANDING_PAGES = [
  {
    path: 'dashboard',
    permissions: [
      ...ROLES,
      ...CONVERSATION_PERMISSIONS,
      CONVERSATION_VIEW_PERMISSION,
    ],
  },
  {
    path: 'contacts',
    permissions: [CONTACT_PERMISSIONS, CONTACT_VIEW_PERMISSION],
  },
  {
    path: 'crm',
    permissions: [CRM_VIEW_PERMISSION],
    isAvailable: isCrmKanbanEnabled,
  },
  { path: 'campaigns', permissions: CAMPAIGN_PERMISSIONS },
  { path: 'reports/overview', permissions: [REPORTS_PERMISSIONS] },
  { path: 'portals', permissions: [PORTAL_PERMISSIONS] },
];

// Opens for every seat (administrator, agent or custom role): a role with none
// of the pages above lands here instead of bouncing off the dashboard forever.
const ALWAYS_OPEN_PAGE = 'profile/settings';

export const defaultRedirectPage = (to, permissions) => {
  const { accountId } = to.params;

  const page = LANDING_PAGES.find(
    ({ permissions: pagePermissions, isAvailable = () => true }) =>
      hasPermissions(pagePermissions, permissions) && isAvailable()
  );

  return `accounts/${accountId}/${page ? page.path : ALWAYS_OPEN_PAGE}`;
};

const validateActiveAccountRoutes = (to, user) => {
  // If the current account is active, then check for the route permissions
  const accountDashboardURL = `accounts/${to.params.accountId}/dashboard`;

  // If the user is trying to access suspended route, redirect them to dashboard
  if (to.name === 'account_suspended') {
    return accountDashboardURL;
  }

  const userPermissions = getUserPermissions(user, to.params.accountId);

  const isAccessible = routeIsAccessibleFor(to, userPermissions);
  if (isAccessible) return null;
  // Fork: a route can name where to go without permission (e.g. who only sees
  // the WhatsApp templates opening "new" lands on the list, not on a blank page).
  const { fallbackPath } = to.meta || {};
  if (fallbackPath) return `accounts/${to.params.accountId}/${fallbackPath}`;
  // Otherwise, the first screen the person can open (#1643).
  const landingPage = defaultRedirectPage(to, userPermissions);
  // Already on the always-open page (an account payload without permissions):
  // stay instead of redirecting to itself forever.
  return to.path?.endsWith(`/${landingPage}`) ? null : landingPage;
};

export const validateLoggedInRoutes = (to, user) => {
  const currentAccount = getCurrentAccount(user, Number(to.params.accountId));
  // If current account is missing, either user does not have
  // access to the account or the account is deleted, return to login screen
  if (!currentAccount) {
    return `app/login`;
  }

  const isCurrentAccountActive = currentAccount.status === 'active';

  if (isCurrentAccountActive) {
    return validateActiveAccountRoutes(to, user);
  }

  // If the current account is not active, only the suspended screen is
  // reachable; administrators can also access billing to restore the account
  const userPermissions = getUserPermissions(user, to.params.accountId);
  const accessibleRoutes = userPermissions.includes('administrator')
    ? ['account_suspended', 'billing_settings_index']
    : ['account_suspended'];

  if (!accessibleRoutes.includes(to.name)) {
    return `accounts/${to.params.accountId}/suspended`;
  }

  // Proceed to the route if none of the above conditions are met
  return null;
};

export const isAConversationRoute = (
  routeName,
  includeBase = false,
  includeExtended = true
) => {
  const baseRoutes = [
    'home',
    'conversation_mentions',
    'conversation_unattended',
    'inbox_dashboard',
    'label_conversations',
    'team_conversations',
    'folder_conversations',
    'conversation_participating',
  ];
  const extendedRoutes = [
    'inbox_conversation',
    'conversation_through_mentions',
    'conversation_through_unattended',
    'conversation_through_inbox',
    'conversations_through_label',
    'conversations_through_team',
    'conversations_through_folders',
    'conversation_through_participating',
  ];

  const routes = [
    ...(includeBase ? baseRoutes : []),
    ...(includeExtended ? extendedRoutes : []),
  ];

  return routes.includes(routeName);
};

export const getConversationDashboardRoute = routeName => {
  switch (routeName) {
    case 'inbox_conversation':
      return 'home';
    case 'conversation_through_mentions':
      return 'conversation_mentions';
    case 'conversation_through_unattended':
      return 'conversation_unattended';
    case 'conversations_through_label':
      return 'label_conversations';
    case 'conversations_through_team':
      return 'team_conversations';
    case 'conversations_through_folders':
      return 'folder_conversations';
    case 'conversation_through_participating':
      return 'conversation_participating';
    case 'conversation_through_inbox':
      return 'inbox_dashboard';
    default:
      return null;
  }
};

export const isAInboxViewRoute = (routeName, includeBase = false) => {
  const baseRoutes = ['inbox_view'];
  const extendedRoutes = ['inbox_view_conversation'];
  const routeNames = includeBase
    ? [...baseRoutes, ...extendedRoutes]
    : extendedRoutes;
  return routeNames.includes(routeName);
};

export const isUpgradePageBypassRoute = routeName =>
  [
    'billing_settings_index',
    'settings_inbox_list',
    'general_settings_index',
    'agent_list',
  ].includes(routeName);
