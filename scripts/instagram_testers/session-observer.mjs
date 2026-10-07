/* eslint-disable no-control-regex, no-underscore-dangle -- Reject unsafe characters and validate the exact Meta form field names. */
import { createHash } from 'node:crypto';
import { isIP } from 'node:net';

export const extraFormKeys = [
  '__aaid',
  '__req',
  '__hs',
  'dpr',
  '__ccg',
  '__rev',
  '__s',
  '__hsi',
  '__dyn',
  'qpl_active_flow_ids',
];

// Read-only browser evidence, 2026-10-07. These public document pins are
// intentionally kept here instead of coming from runtime metadata; their
// provenance is recorded in docs/audit/995-loading-contract-20261007.md.
export const loadingQueryDocumentSha256 = Object.freeze({
  GeoNextAppControllerContainerQuery:
    'e3050f6f5039fae023bca06560b9aba52597bccd045d0e84bf1388e8abeca508',
  DeveloperHeaderComponentContainerQuery:
    '34abd55916c1d35a7c4f9aa7db399dd263dbc0b2bb5b85ac93df704b4050e7e2',
  DeveloperAppVisibilityToggleLazyLoadedQuery:
    'eb759a93022e512816320a08284e22585c2eafb0476dbea91baf2c1431838f6e',
  DeveloperAppBannerQuery:
    '108dc0b68c940503ae888f48ab296b1e6e1ac323398ef236f4968db71b2c7abd',
  DeveloperAppDashboardSidebarNavigationV2Query:
    '998762536e2ad143534eb74762e333c33d763c5bc97b52df2fb8d828f5f5582b',
});

const loadingQueryVariableNames = Object.freeze({
  GeoNextAppControllerContainerQuery: Object.freeze(['appID']),
  DeveloperHeaderComponentContainerQuery: Object.freeze([
    'businessID',
    'businessID_is_null',
  ]),
  DeveloperAppVisibilityToggleLazyLoadedQuery: Object.freeze(['appID']),
  DeveloperAppBannerQuery: Object.freeze(['appID']),
  DeveloperAppDashboardSidebarNavigationV2Query: Object.freeze(['appID']),
});

const numeric = value =>
  typeof value === 'string' && /^[0-9]{1,40}$/.test(value);
const safe = value =>
  typeof value === 'string' &&
  value.length > 0 &&
  Buffer.byteLength(value) <= 32768 &&
  !/[\x00-\x1f\x7f]/.test(value);
const requireSafe = condition => {
  if (!condition) throw new Error('session_update_rejected');
};

export function proxyConfiguration(env) {
  const authMode = env.INSTAGRAM_TESTER_PROXY_AUTH_MODE;
  const hasUsername =
    env.INSTAGRAM_TESTER_PROXY_USERNAME !== undefined &&
    env.INSTAGRAM_TESTER_PROXY_USERNAME !== '';
  const hasPassword =
    env.INSTAGRAM_TESTER_PROXY_PASSWORD !== undefined &&
    env.INSTAGRAM_TESTER_PROXY_PASSWORD !== '';
  const config = {
    host: env.INSTAGRAM_TESTER_PROXY_HOST,
    port: env.INSTAGRAM_TESTER_PROXY_PORT,
    authMode,
  };
  requireSafe(typeof config.host === 'string' && isIP(config.host) === 4);
  requireSafe(config.authMode === 'ip' && !hasUsername && !hasPassword);
  requireSafe(
    numeric(config.port) &&
      Number(config.port) >= 1 &&
      Number(config.port) <= 65535
  );
  const identity = env.INSTAGRAM_TESTER_PROXY_IDENTITY;
  const local = config.host.split('.')[0] === '127';
  requireSafe(identity !== undefined || !local);
  if (identity !== undefined) {
    requireSafe(typeof identity === 'string');
    const parts = identity.split(':');
    const [host, port] = parts;
    requireSafe(
      parts.length === 2 &&
        isIP(host) === 4 &&
        host.split('.')[0] !== '127' &&
        port.length > 0 &&
        [...port].every(char => '0123456789'.includes(char)) &&
        Number(port) >= 1 &&
        Number(port) <= 65535 &&
        String(Number(port)) === port &&
        (local || identity === `${config.host}:${Number(config.port)}`)
    );
    config.identity = identity;
  }
  return Object.freeze(config);
}

export function configuration(env) {
  const config = {
    ...proxyConfiguration(env),
    appId: env.INSTAGRAM_META_DEVELOPER_APP_ID,
    businessId: env.INSTAGRAM_META_BUSINESS_ID,
    docId: env.INSTAGRAM_TESTER_ROLES_DOC_ID,
    adminId: env.INSTAGRAM_TESTER_ADMIN_USER_ID,
  };
  requireSafe(
    [config.appId, config.businessId, config.docId, config.adminId].every(
      numeric
    )
  );
  config.rolesUrl = `https://developers.facebook.com/apps/${config.appId}/roles/roles/?business_id=${config.businessId}`;
  config.proxyFingerprint = createHash('sha256')
    .update(
      config.identity === undefined
        ? `${config.host.toLowerCase()}:${Number(config.port)}:${config.authMode}`
        : `${config.identity}:${config.authMode}`
    )
    .digest('hex');
  return Object.freeze(config);
}

// Validates only the form fields that identify the browser's observed roles
// query. Headers/cookies and the response remain the responsibility of the
// observer; the browser route gate must not inspect or log either.
export function rolesQueryFields(body, config) {
  requireSafe(typeof body === 'string' && Buffer.byteLength(body) <= 262144);
  const entries = [...new URLSearchParams(body)];
  requireSafe(new Set(entries.map(([key]) => key)).size === entries.length);
  const fields = Object.fromEntries(entries);
  if (fields.fb_api_req_friendly_name !== 'RolesTable_Query') return null;
  requireSafe(
    config &&
      fields.doc_id === config.docId &&
      fields.__bid === config.businessId &&
      fields.__user === config.adminId
  );
  requireSafe(!('av' in fields) || fields.av === config.adminId);
  const variables = fields.variables?.match(
    /^\s*\{\s*"app_id"\s*:\s*"([0-9]{1,40})"\s*\}\s*$/
  );
  requireSafe(variables && variables[1] === config.appId);
  return fields;
}

function exactLoadingVariables(name, fields, config) {
  const expectedKeys = loadingQueryVariableNames[name];
  if (!expectedKeys) return false;
  let variables;
  try {
    variables = JSON.parse(fields.variables);
  } catch {
    return false;
  }
  if (!variables || typeof variables !== 'object' || Array.isArray(variables))
    return false;
  const keys = Object.keys(variables).sort();
  const sortedExpectedKeys = [...expectedKeys].sort();
  if (
    keys.length !== sortedExpectedKeys.length ||
    !keys.every((key, index) => key === sortedExpectedKeys[index])
  )
    return false;
  if (name === 'DeveloperHeaderComponentContainerQuery')
    return (
      variables.businessID === config.businessId &&
      variables.businessID_is_null === false
    );
  return variables.appID === config.appId;
}

export function loadingQueryFields(body, config) {
  requireSafe(typeof body === 'string' && Buffer.byteLength(body) <= 262144);
  const entries = [...new URLSearchParams(body)];
  requireSafe(new Set(entries.map(([key]) => key)).size === entries.length);
  const fields = Object.fromEntries(entries);
  const name = fields.fb_api_req_friendly_name;
  if (!Object.prototype.hasOwnProperty.call(loadingQueryDocumentSha256, name))
    return null;
  requireSafe(
    config &&
      numeric(fields.doc_id) &&
      fields.__bid === config.businessId &&
      fields.__user === config.adminId &&
      fields.av === config.adminId
  );
  const documentSha256 = createHash('sha256')
    .update(fields.doc_id)
    .digest('hex');
  requireSafe(documentSha256 === loadingQueryDocumentSha256[name]);
  return exactLoadingVariables(name, fields, config) ? fields : null;
}

// Observes a request emitted by the authorized browser. Never constructs or
// retries a RolesTable request, performs a login, or works around a challenge.
export function observedSession({ url, method, headers, body }, config) {
  if (
    url !== 'https://developers.facebook.com/api/graphql/' ||
    method !== 'POST'
  )
    return null;
  const fields = rolesQueryFields(body, config);
  if (!fields) return null;
  requireSafe(
    !headers['x-fb-friendly-name'] ||
      headers['x-fb-friendly-name'] === 'RolesTable_Query'
  );
  requireSafe(!headers['x-fb-lsd'] || headers['x-fb-lsd'] === fields.lsd);
  const cookie = headers.cookie;
  requireSafe(safe(cookie));
  const cookies = cookie
    .split(';')
    .map(item => item.trim())
    .filter(Boolean)
    .map(item => {
      const index = item.indexOf('=');
      requireSafe(index > 0);
      return [item.slice(0, index), item.slice(index + 1)];
    });
  requireSafe(new Set(cookies.map(([key]) => key)).size === cookies.length);
  requireSafe(Object.fromEntries(cookies).c_user === config.adminId);
  const session = {
    cookie,
    user_agent: headers['user-agent'],
    user_id: fields.__user,
    fb_dtsg: fields.fb_dtsg,
    lsd: fields.lsd,
    jazoest: fields.jazoest,
  };
  requireSafe(Object.values(session).every(safe));
  session.extra_form = Object.fromEntries(
    extraFormKeys.filter(key => key in fields).map(key => [key, fields[key]])
  );
  requireSafe(Object.values(session.extra_form).every(safe));
  return session;
}

export function safeBrowserLocation(url, config) {
  try {
    const location = new URL(url);
    return (
      location.origin === 'https://developers.facebook.com' &&
      location.pathname === `/apps/${config.appId}/roles/roles/` &&
      location.searchParams.get('business_id') === config.businessId
    );
  } catch {
    return false;
  }
}

export function validateRolesResponse(body) {
  requireSafe(typeof body === 'string' && Buffer.byteLength(body) <= 2097152);
  const document = JSON.parse(body.trim().replace(/^for \(;;\);/, ''));
  const clean = value => {
    if (Array.isArray(value)) return value.every(clean);
    if (!value || typeof value !== 'object') return true;
    return (
      value.error == null &&
      (value.errors == null ||
        (Array.isArray(value.errors) && value.errors.length === 0)) &&
      Object.values(value).every(clean)
    );
  };
  const complete = value =>
    !('page_info' in value) || value.page_info?.has_next_page === false;
  const container = document?.data?.get_app_roles;
  requireSafe(
    clean(document) &&
      container &&
      Array.isArray(container.app_roles) &&
      complete(container)
  );
  container.app_roles.forEach(group => {
    requireSafe(
      group &&
        typeof group.role === 'string' &&
        Array.isArray(group.users) &&
        complete(group)
    );
    if (group.role === 'instagram testers') {
      requireSafe(
        group.users.every(
          user =>
            numeric(user?.id) && ['PENDING', 'CONFIRMED'].includes(user.status)
        )
      );
    }
  });
  return true;
}
