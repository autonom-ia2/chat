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
const LEGACY_ROLES_QUERY = 'RolesTable_Query';
const APP_CONTEXT_QUERY = 'GeoNextAppControllerContainerQuery';

export function rolesQueryFields(body, config) {
  requireSafe(typeof body === 'string' && Buffer.byteLength(body) <= 262144);
  const entries = [...new URLSearchParams(body)];
  requireSafe(new Set(entries.map(([key]) => key)).size === entries.length);
  const fields = Object.fromEntries(entries);
  const query = fields.fb_api_req_friendly_name;
  if (![LEGACY_ROLES_QUERY, APP_CONTEXT_QUERY].includes(query)) return null;
  requireSafe(
    config &&
      fields.__bid === config.businessId &&
      fields.__user === config.adminId
  );
  requireSafe(!('av' in fields) || fields.av === config.adminId);
  let variables;
  if (query === LEGACY_ROLES_QUERY) {
    requireSafe(fields.doc_id === config.docId);
    variables = fields.variables?.match(
      /^\s*\{\s*"app_id"\s*:\s*"([0-9]{1,40})"\s*\}\s*$/
    );
  } else {
    // Meta no longer emits RolesTable_Query on the roles page. Keep this
    // replacement fail-closed: exact persisted-operation name and the same
    // canonical doc-id binding used by the legacy contract.
    requireSafe(fields.doc_id === config.docId);
    variables = fields.variables?.match(
      /^\s*\{\s*"appID"\s*:\s*"([0-9]{1,40})"\s*\}\s*$/
    );
  }
  requireSafe(variables && variables[1] === config.appId);
  return fields;
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
      headers['x-fb-friendly-name'] === fields.fb_api_req_friendly_name
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

export function validateRolesResponse(body, query, config) {
  const selectedQuery = query || LEGACY_ROLES_QUERY;
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
  requireSafe(clean(document));
  if (selectedQuery === APP_CONTEXT_QUERY) {
    const application = document?.data?.fetch__Application;
    requireSafe(
      config &&
        application &&
        typeof application === 'object' &&
        !Array.isArray(application) &&
        String(application.id) === config.appId
    );
    return true;
  }
  requireSafe(selectedQuery === LEGACY_ROLES_QUERY);
  const complete = value =>
    !('page_info' in value) || value.page_info?.has_next_page === false;
  const container = document?.data?.get_app_roles;
  requireSafe(
    container && Array.isArray(container.app_roles) && complete(container)
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
