/* eslint-disable no-await-in-loop, no-restricted-syntax, no-continue -- Node parsing and UI steps run sequentially. */
/* eslint-disable no-underscore-dangle -- Preserve Meta's canonical form-field names. */
import {
  rolesQueryFields,
  safeBrowserLocation,
  validateRolesResponse,
} from './session-observer.mjs';

const ORIGIN = 'https://developers.facebook.com';
const GRAPHQL_URL = `${ORIGIN}/api/graphql/`;
const SEARCH_PATH = '/roles/instagram/typeahead/user/';
const INVITE_PATH_SUFFIX = '/async/instagram/roles/add/';
const ROLES_QUERY_NAME = 'RolesTable_Query';
const ROLE = 'instagram testers';
const RESPONSE_MAX = 2 * 1024 * 1024;
const MAX_SEARCH_ENTRIES = 100;
const MAX_UI_SOURCE_CHARS = 120;
const MAX_UI_SOURCE_VALUES = 64;
const MAX_UI_OPTIONS = 500;
const UI_WAIT_MS = 5000;
const UI_POLL_MS = 100;
const INVITE_CLICK_TIMEOUT_MS = 5000;
const INVITE_REQUEST_WAIT_MS = 5000;
const MIN_INVITE_RESPONSE_WAIT_MS = 10000;
const INVITE_RESPONSE_TIMEOUT_MS = 30000;
const INVITE_PERMIT_MAX_MS = 30000;
// What an invite still needs after its permit: click, request and the
// shortest response wait worth starting a write for.
const INVITE_AFTER_PERMIT_MS =
  INVITE_CLICK_TIMEOUT_MS +
  INVITE_REQUEST_WAIT_MS +
  MIN_INVITE_RESPONSE_WAIT_MS;
// Read-only observer tasks never write, so cleanup may stop waiting for them.
const TASK_SETTLE_MS = 2000;
// Callers without a manager deadline get the manager's 120 s operation scope
// minus its 35 s completion reserve.
const DEFAULT_EXECUTION_BUDGET_MS = 85000;
const WARM_FETCH_TIMEOUT_MS = 30000;
const WARM_META_PAGE = 'warm_meta_page';
const WARM_SOURCES = new Set(['manager_refresh', 'same_page_refresh']);
const WARM_INVALIDATION_REASONS = new Set([
  'page_closed',
  'page_changed',
  'configuration_changed',
  'roles_anchor_changed',
  'roles_response_invalid',
  'roles_http_error',
  'csrf_expired',
  'proxy_error',
  'aborted',
  'refresh_replaced',
  'disposed',
  'unknown',
]);
const WARM_TERMINAL_REASONS = new Set([
  'page_closed',
  'configuration_changed',
  'roles_anchor_changed',
  'roles_response_invalid',
  'roles_http_error',
  'csrf_expired',
  'proxy_error',
  'aborted',
  'refresh_replaced',
  'disposed',
]);
const DIALOG_CANCEL_NAMES = /^(?:Cancel|Cancelar)$/i;
const DIALOG_CLOSE_NAMES = /^(?:Close|Fechar)$/i;
const TYPEAHEAD_FIELDS = Object.freeze([
  '__aaid',
  '__bid',
  '__user',
  '__a',
  '__req',
  '__hs',
  'dpr',
  '__ccg',
  '__rev',
  '__s',
  '__hsi',
  '__dyn',
  'fb_dtsg',
  'jazoest',
  'lsd',
  'qpl_active_flow_ids',
]);
const TYPEAHEAD_FIELD_SET = new Set(TYPEAHEAD_FIELDS);
const TYPEAHEAD_CREDENTIAL_FIELDS = Object.freeze([
  'fb_dtsg',
  'jazoest',
  'lsd',
]);
const INVITE_FIELDS = Object.freeze([
  ...TYPEAHEAD_FIELDS,
  'role',
  'user_id_or_vanitys[0]',
  'reload_on_success',
]);
const INVITE_FIELD_SET = new Set(INVITE_FIELDS);
const ACTIONS = new Set(['search', 'status', 'authorization', 'invite']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const NUMERIC = /^[0-9]{1,40}$/;
const USERNAME = /^[a-z0-9._]{1,30}$/;
const SAFE_ERRORS = new Set([
  'invalid_username',
  'invalid_selection',
  'meta_unavailable',
  'meta_session_expired',
  'unknown_status',
  'invite_rejected',
  'invite_unknown',
  'rate_limited',
  'forbidden',
  'not_enabled',
  'busy',
  'proxy_unavailable',
  'session_update_rejected',
  'operator_required',
]);

class BrowserOperationError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function fail(code) {
  throw new BrowserOperationError(code);
}

function numeric(value) {
  return typeof value === 'string' && NUMERIC.test(value);
}

function username(value) {
  return typeof value === 'string' && USERNAME.test(value);
}

function uuid(value) {
  return typeof value === 'string' && UUID.test(value);
}

function normalizeUsername(value) {
  if (!username(value)) fail('invalid_username');
  return value.toLowerCase();
}

function requestValue(request, key) {
  const value = request?.[key];
  return typeof value === 'function' ? value.call(request) : value;
}

function requestUrl(request) {
  return requestValue(request, 'url');
}

function requestMethod(request) {
  return String(requestValue(request, 'method') || '').toUpperCase();
}

function requestBody(request) {
  const value = requestValue(request, 'postData');
  return typeof value === 'string' ? value : '';
}

function responseValue(response, key) {
  const value = response?.[key];
  return typeof value === 'function' ? value.call(response) : value;
}

function responseStatus(response) {
  const value = responseValue(response, 'status');
  return Number.isSafeInteger(value) ? value : Number(value);
}

function operationNow(now) {
  const value = typeof now === 'function' ? now() : Date.now();
  return Number.isFinite(value) ? value : Date.now();
}

function timestamp(now) {
  return new Date(operationNow(now)).toISOString();
}

function baseEnvelope(request, now) {
  return {
    type: 'browser_operation',
    operation: 'complete',
    action: request?.action,
    id: request?.id,
    request_id: request?.request_id,
    claim: request?.claim,
    captured_at: timestamp(now),
  };
}

function successEnvelope(request, payload, now) {
  return { ...baseEnvelope(request, now), ...payload };
}

function validateConfiguration(config) {
  if (
    !config ||
    !numeric(config.appId) ||
    !numeric(config.businessId) ||
    !numeric(config.docId) ||
    !numeric(config.adminId) ||
    typeof config.rolesUrl !== 'string' ||
    !safeBrowserLocation(config.rolesUrl, config)
  )
    fail('invalid_selection');
}

function validateRequest(request, config) {
  if (
    !request ||
    typeof request !== 'object' ||
    !ACTIONS.has(request.action) ||
    !uuid(request.id) ||
    !uuid(request.request_id) ||
    !uuid(request.claim) ||
    request.app_id !== config.appId
  )
    fail('invalid_selection');
  if (normalizeUsername(request.username) !== request.username)
    fail('invalid_username');
  if (request.action !== 'search' && !numeric(request.target_id))
    fail('invalid_selection');
}

function abortReason(signal) {
  return signal?.reason instanceof Error
    ? signal.reason
    : new BrowserOperationError('meta_unavailable');
}

function withSignal(promise, signal) {
  if (!signal) return Promise.resolve(promise);
  if (signal.aborted) return Promise.reject(abortReason(signal));
  return new Promise((resolve, reject) => {
    const abort = () => {
      signal.removeEventListener('abort', abort);
      reject(abortReason(signal));
    };
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve(promise).then(
      value => {
        signal.removeEventListener('abort', abort);
        if (signal.aborted) reject(abortReason(signal));
        else resolve(value);
      },
      error => {
        signal.removeEventListener('abort', abort);
        reject(error);
      }
    );
  });
}

function delay(ms, signal) {
  return withSignal(
    new Promise(resolve => {
      setTimeout(resolve, ms);
    }),
    signal
  );
}

function cleanDocument(value) {
  if (Array.isArray(value)) return value.every(cleanDocument);
  if (!value || typeof value !== 'object') return true;
  if (value.error !== undefined && value.error !== null) return false;
  if (
    value.errors !== undefined &&
    value.errors !== null &&
    !(Array.isArray(value.errors) && value.errors.length === 0)
  )
    return false;
  return Object.values(value).every(cleanDocument);
}

function parseDocument(body) {
  if (typeof body !== 'string' || Buffer.byteLength(body) > RESPONSE_MAX)
    fail('meta_unavailable');
  const text = body.trim().startsWith('for (;;);')
    ? body.trim().slice('for (;;);'.length)
    : body.trim();
  let document;
  try {
    document = JSON.parse(text);
  } catch {
    fail('meta_unavailable');
  }
  if (
    !document ||
    typeof document !== 'object' ||
    Array.isArray(document) ||
    !cleanDocument(document)
  )
    fail('meta_unavailable');
  return document;
}

function validAvatar(value) {
  if (value === null || value === undefined) return true;
  if (typeof value !== 'string' || value.length > 4096) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      Boolean(url.hostname) &&
      !url.username &&
      !url.password
    );
  } catch {
    return false;
  }
}

export function parseSearchCandidates(body) {
  const document = parseDocument(body);
  const entries = document.payload?.entries;
  if (!Array.isArray(entries) || entries.length > MAX_SEARCH_ENTRIES)
    fail('meta_unavailable');
  const ids = new Set();
  const results = entries.map(entry => {
    const valid =
      entry &&
      typeof entry === 'object' &&
      !Array.isArray(entry) &&
      numeric(entry.uniqueID) &&
      username(entry.text) &&
      typeof entry.subtitle === 'string' &&
      entry.subtitle.length <= 500 &&
      validAvatar(entry.photo) &&
      !ids.has(entry.uniqueID);
    if (!valid) fail('meta_unavailable');
    ids.add(entry.uniqueID);
    return {
      id: entry.uniqueID,
      username: entry.text.toLowerCase(),
      name: entry.subtitle,
      avatar_url: entry.photo ?? null,
    };
  });
  return results;
}

function completeContainer(container) {
  return (
    !Object.prototype.hasOwnProperty.call(container, 'page_info') ||
    (container.page_info && container.page_info.has_next_page === false)
  );
}

const ROLE_STATUSES = new Map([
  ['PENDING', 'pending'],
  ['CONFIRMED', 'accepted'],
]);

// Maps every tester in a complete roster to its status. A roster without the
// testers group is empty (everyone is absent); anything incomplete, malformed
// or contradictory is unknown_status.
export function rolesStatusMap(document) {
  const container = document?.data?.get_app_roles;
  if (!container || typeof container !== 'object' || Array.isArray(container))
    fail('unknown_status');
  const groups = container.app_roles;
  if (!Array.isArray(groups) || !completeContainer(container))
    fail('unknown_status');
  const statuses = new Map();
  for (const group of groups) {
    if (
      !group ||
      typeof group !== 'object' ||
      Array.isArray(group) ||
      typeof group.role !== 'string' ||
      !Array.isArray(group.users) ||
      !completeContainer(group)
    )
      fail('unknown_status');
    if (group.role !== ROLE) continue;
    for (const user of group.users) {
      if (
        !user ||
        typeof user !== 'object' ||
        Array.isArray(user) ||
        !numeric(user.id) ||
        !ROLE_STATUSES.has(user.status)
      )
        fail('unknown_status');
      const status = ROLE_STATUSES.get(user.status);
      if (statuses.has(user.id) && statuses.get(user.id) !== status)
        fail('unknown_status');
      statuses.set(user.id, status);
    }
  }
  return statuses;
}

export function parseRolesStatus(body, targetId) {
  if (!numeric(targetId)) fail('invalid_selection');
  return rolesStatusMap(parseDocument(body)).get(targetId) ?? 'absent';
}

function roleRequestMetadata(request, config) {
  if (requestUrl(request) !== GRAPHQL_URL || requestMethod(request) !== 'POST')
    return null;
  const body = requestBody(request);
  let entries;
  try {
    entries = [...new URLSearchParams(body)];
  } catch {
    return null;
  }
  if (
    !entries.some(
      ([key, value]) =>
        key === 'fb_api_req_friendly_name' && value === ROLES_QUERY_NAME
    )
  )
    return null;
  if (Buffer.byteLength(body) > 262144) return { valid: false };
  try {
    const fields = rolesQueryFields(body, config);
    const aaids = new URLSearchParams(body).getAll('__aaid');
    return {
      valid: Boolean(fields) && aaids.length === 1 && numeric(aaids[0]),
      aaid: aaids.length === 1 && numeric(aaids[0]) ? aaids[0] : null,
    };
  } catch {
    return { valid: false, aaid: null };
  }
}

function typeaheadPath(url) {
  try {
    const parsed = new URL(url);
    return (
      parsed.origin === ORIGIN &&
      parsed.pathname === SEARCH_PATH &&
      parsed.username === '' &&
      parsed.password === '' &&
      parsed.hash === ''
    );
  } catch {
    return false;
  }
}

function invitePath(url, config) {
  try {
    const parsed = new URL(url);
    return (
      parsed.origin === ORIGIN &&
      parsed.pathname === `/apps/${config.appId}${INVITE_PATH_SUFFIX}` &&
      parsed.username === '' &&
      parsed.password === '' &&
      parsed.search === '' &&
      parsed.hash === ''
    );
  } catch {
    return false;
  }
}

export function typeaheadRequestMetadata(
  request,
  config,
  targetUsername,
  rolesAaid = null
) {
  const url = requestUrl(request);
  if (!typeaheadPath(url) || requestMethod(request) !== 'POST') return null;
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return { valid: false };
  }
  const queryValues = parsed.searchParams.getAll('value');
  const queryEntries = [...parsed.searchParams];
  const body = requestBody(request);
  if (Buffer.byteLength(body) > 262144) return { valid: false };
  let entries;
  try {
    entries = [...new URLSearchParams(body)];
  } catch {
    return { valid: false };
  }
  const keys = entries.map(([key]) => key);
  const values = Object.fromEntries(entries);
  const exactFields =
    entries.length === TYPEAHEAD_FIELDS.length &&
    new Set(keys).size === TYPEAHEAD_FIELDS.length &&
    keys.every(key => TYPEAHEAD_FIELD_SET.has(key));
  const queryExact =
    queryEntries.length === 1 &&
    queryEntries[0][0] === 'value' &&
    queryValues.length === 1 &&
    (queryValues[0] === targetUsername ||
      queryValues[0] === `@${targetUsername}`);
  const identityExact =
    values.__bid === config.businessId &&
    values.__user === config.adminId &&
    values.__a === '1' &&
    numeric(values.__aaid) &&
    numeric(rolesAaid) &&
    values.__aaid === rolesAaid;
  const credentialsPresent = TYPEAHEAD_CREDENTIAL_FIELDS.every(
    key => typeof values[key] === 'string' && values[key].length > 0
  );
  return {
    valid: exactFields && queryExact && identityExact && credentialsPresent,
    aaid: numeric(values.__aaid) ? values.__aaid : null,
  };
}

function inviteRequestMetadata(
  request,
  config,
  state,
  targetId,
  targetUsername
) {
  const url = requestUrl(request);
  if (!invitePath(url, config) || requestMethod(request) !== 'POST')
    return null;
  const body = requestBody(request);
  if (Buffer.byteLength(body) > 262144) return { valid: false };
  let entries;
  try {
    entries = [...new URLSearchParams(body)];
  } catch {
    return { valid: false };
  }
  const keys = entries.map(([key]) => key);
  if (
    entries.length !== INVITE_FIELDS.length ||
    new Set(keys).size !== INVITE_FIELDS.length ||
    !keys.every(key => INVITE_FIELD_SET.has(key))
  )
    return { valid: false };
  const values = Object.fromEntries(entries);
  const commonPins =
    values.__bid === config.businessId &&
    values.__user === config.adminId &&
    values.__a === '1' &&
    numeric(values.__aaid) &&
    numeric(state.rolesAaid) &&
    values.__aaid === state.rolesAaid;
  const credentialsPresent = TYPEAHEAD_CREDENTIAL_FIELDS.every(
    key => typeof values[key] === 'string' && values[key].length > 0
  );
  const targetMatched =
    values.role === ROLE &&
    values['user_id_or_vanitys[0]'] === targetId &&
    values.reload_on_success === 'false' &&
    typeof targetUsername === 'string' &&
    username(targetUsername);
  return {
    valid:
      commonPins &&
      credentialsPresent &&
      targetMatched &&
      state.targetCandidateUnique === true,
    common_pins_matched: commonPins,
    credentials_present: credentialsPresent,
    target_matched: targetMatched,
  };
}

function responseError(status, fallback) {
  if (status === 401 || status === 403) return 'meta_session_expired';
  if (status === 407) return 'proxy_unavailable';
  if (status === 429) return 'rate_limited';
  return fallback;
}

function warmConfigurationFingerprint(config) {
  return [
    config?.appId,
    config?.businessId,
    config?.docId,
    config?.adminId,
    config?.rolesUrl,
    config?.proxyFingerprint || null,
  ]
    .map(value => (value === undefined ? null : value))
    .join('\u001f');
}

function pageFromRequest(value) {
  try {
    const frame =
      typeof value?.frame === 'function' ? value.frame() : undefined;
    return typeof frame?.page === 'function' ? frame.page() : null;
  } catch {
    return null;
  }
}

function warmPageClosed(page) {
  try {
    return typeof page?.isClosed === 'function' && page.isClosed();
  } catch {
    return true;
  }
}

function warmIdentityMatches(warm, page, config) {
  return (
    warm?.kind === WARM_META_PAGE &&
    warm.disposed !== true &&
    warm.page === page &&
    warm.configurationFingerprint === warmConfigurationFingerprint(config)
  );
}

export function invalidateWarmMetaPage(warm, reason = 'unknown') {
  if (!warm || warm.kind !== WARM_META_PAGE) return false;
  const nextReason = WARM_INVALIDATION_REASONS.has(reason) ? reason : 'unknown';
  const preserveTerminalReason =
    nextReason === 'page_changed' &&
    WARM_TERMINAL_REASONS.has(warm.invalidReason);
  warm.valid = false;
  warm.invalidReason = preserveTerminalReason ? warm.invalidReason : nextReason;
  warm.formBody = null;
  warm.rolesAaid = null;
  warm.source = null;
  warm.acceptedAt = null;
  warm.generation += 1;
  warm.refreshing = false;
  return true;
}

function warmFailure(warm, reason, code) {
  invalidateWarmMetaPage(warm, reason);
  return fail(code);
}

function warmInvalidationError(warm) {
  switch (warm?.invalidReason) {
    case 'configuration_changed':
    case 'csrf_expired':
      return 'meta_session_expired';
    case 'roles_anchor_changed':
    case 'roles_response_invalid':
      return 'unknown_status';
    case 'page_changed':
      return 'meta_session_expired';
    case 'page_closed':
    case 'proxy_error':
    case 'roles_http_error':
    case 'aborted':
    case 'refresh_replaced':
    case 'disposed':
    case 'unknown':
    default:
      return 'meta_unavailable';
  }
}

function warmCanRecoverCold(warm, page, config) {
  return (
    warm?.kind === WARM_META_PAGE &&
    warm.disposed !== true &&
    warm.valid !== true &&
    warm.invalidReason === 'page_changed' &&
    safeBrowserLocation(page?.url?.(), config)
  );
}

function warmRefreshRequired(warm, page, config) {
  if (!warm) return false;
  if (!warmIdentityMatches(warm, page, config)) fail('meta_session_expired');
  if (warm.valid) return true;
  if (warmCanRecoverCold(warm, page, config)) return false;
  return fail(warmInvalidationError(warm));
}

export function createWarmMetaPage({
  page,
  configuration,
  now = Date.now,
} = {}) {
  validateConfiguration(configuration);
  if (
    !page ||
    typeof page.on !== 'function' ||
    typeof page.off !== 'function' ||
    typeof page.evaluate !== 'function'
  )
    fail('meta_unavailable');
  const warm = {
    kind: WARM_META_PAGE,
    page,
    configuration,
    configurationFingerprint: warmConfigurationFingerprint(configuration),
    valid: false,
    invalidReason: 'unknown',
    generation: 0,
    formBody: null,
    rolesAaid: null,
    source: null,
    acceptedAt: null,
    refreshing: false,
    disposed: false,
    now,
    onClose: null,
    onFrameNavigated: null,
    dispose() {
      if (warm.disposed) return;
      warm.disposed = true;
      invalidateWarmMetaPage(warm, 'disposed');
      try {
        page.off('close', warm.onClose);
        page.off('framenavigated', warm.onFrameNavigated);
      } catch {
        // Page shutdown owns listener cleanup when Playwright has already closed.
      }
    },
  };
  warm.onClose = () => invalidateWarmMetaPage(warm, 'page_closed');
  warm.onFrameNavigated = frame => {
    try {
      if (typeof page.mainFrame !== 'function' || frame === page.mainFrame())
        invalidateWarmMetaPage(warm, 'page_changed');
    } catch {
      invalidateWarmMetaPage(warm, 'page_changed');
    }
  };
  page.on('close', warm.onClose);
  page.on('framenavigated', warm.onFrameNavigated);
  return warm;
}

export function acceptFreshRolesResponse(
  warm,
  {
    page,
    configuration,
    request,
    response,
    body,
    source = 'manager_refresh',
  } = {}
) {
  if (!warm || warm.kind !== WARM_META_PAGE) fail('invalid_selection');
  if (!WARM_SOURCES.has(source))
    warmFailure(warm, 'unknown', 'invalid_selection');
  if (!warmIdentityMatches(warm, page, configuration))
    warmFailure(warm, 'configuration_changed', 'meta_session_expired');
  if (warmPageClosed(page))
    warmFailure(warm, 'page_closed', 'meta_unavailable');
  if (!safeBrowserLocation(page.url(), configuration))
    warmFailure(warm, 'page_changed', 'meta_session_expired');
  const responseRequest = responseValue(response, 'request');
  if (
    !request ||
    !response ||
    responseRequest !== request ||
    (pageFromRequest(request) && pageFromRequest(request) !== page) ||
    (pageFromRequest(responseRequest) &&
      pageFromRequest(responseRequest) !== page)
  )
    warmFailure(warm, 'roles_response_invalid', 'unknown_status');
  const metadata = roleRequestMetadata(request, configuration);
  if (!metadata?.valid || !metadata.aaid)
    warmFailure(warm, 'roles_response_invalid', 'unknown_status');
  if (warm.valid && warm.rolesAaid && warm.rolesAaid !== metadata.aaid)
    warmFailure(warm, 'roles_anchor_changed', 'unknown_status');
  const status = responseStatus(response);
  if (status === 401 || status === 403)
    warmFailure(warm, 'csrf_expired', 'meta_session_expired');
  if (status !== 200)
    warmFailure(
      warm,
      'roles_http_error',
      responseError(status, 'meta_unavailable')
    );
  if (typeof body !== 'string' || Buffer.byteLength(body) > RESPONSE_MAX)
    warmFailure(warm, 'roles_response_invalid', 'unknown_status');
  try {
    validateRolesResponse(body);
    parseDocument(body);
  } catch {
    warmFailure(warm, 'roles_response_invalid', 'unknown_status');
  }
  const formBody = requestBody(request);
  if (!formBody) warmFailure(warm, 'roles_response_invalid', 'unknown_status');
  warm.valid = true;
  warm.invalidReason = null;
  warm.formBody = formBody;
  warm.rolesAaid = metadata.aaid;
  warm.source = source;
  warm.acceptedAt = operationNow(warm.now);
  warm.generation += 1;
  return Object.freeze({
    accepted: true,
    generation: warm.generation,
    source,
  });
}

export async function refreshWarmMetaPage(
  warm,
  { page, configuration, signal } = {}
) {
  if (!warmIdentityMatches(warm, page, configuration))
    warmFailure(warm, 'configuration_changed', 'meta_session_expired');
  if (!warm.valid || !warm.formBody || !warm.rolesAaid)
    warmFailure(warm, 'unknown', 'meta_unavailable');
  if (warmPageClosed(page))
    warmFailure(warm, 'page_closed', 'meta_unavailable');
  if (!safeBrowserLocation(page.url(), configuration))
    warmFailure(warm, 'page_changed', 'meta_session_expired');
  if (warm.refreshing) fail('busy');
  warm.refreshing = true;
  let evaluation;
  const abortToken = `${warm.generation}:${operationNow(warm.now)}`;
  let abortPromise;
  const abortInPage = async () => {
    try {
      await page.evaluate(token => {
        const registry = window.__chat2youWarmRolesFetches;
        registry?.get(token)?.abort();
      }, abortToken);
    } catch {
      // Page shutdown is handled by the outer cleanup and invalidation below.
    }
  };
  const abort = () => {
    abortPromise ||= abortInPage();
  };
  signal?.addEventListener('abort', abort, { once: true });
  try {
    signal?.throwIfAborted();
    evaluation = page.evaluate(
      async ({ url, body, timeoutMs, token }) => {
        const registryKey = '__chat2youWarmRolesFetches';
        const registry =
          window[registryKey] instanceof Map ? window[registryKey] : new Map();
        window[registryKey] = registry;
        const controller = new AbortController();
        registry.set(token, controller);
        const timer = window.setTimeout(() => controller.abort(), timeoutMs);
        try {
          const response = await fetch(url, {
            method: 'POST',
            credentials: 'include',
            cache: 'no-store',
            redirect: 'error',
            headers: {
              'content-type': 'application/x-www-form-urlencoded',
            },
            body,
            signal: controller.signal,
          });
          return response.status;
        } finally {
          window.clearTimeout(timer);
          registry.delete(token);
        }
      },
      {
        url: GRAPHQL_URL,
        body: warm.formBody,
        timeoutMs: WARM_FETCH_TIMEOUT_MS,
        token: abortToken,
      }
    );
    const status = await withSignal(evaluation, signal);
    if (!Number.isSafeInteger(status))
      warmFailure(warm, 'roles_response_invalid', 'unknown_status');
    if (status === 401 || status === 403)
      warmFailure(warm, 'csrf_expired', 'meta_session_expired');
    if (status !== 200)
      warmFailure(
        warm,
        'roles_http_error',
        responseError(status, 'meta_unavailable')
      );
    return Object.freeze({ status: 200, generation: warm.generation });
  } catch (error) {
    // The in-page fetch has its own AbortController. Drain its promise before
    // returning so a pending browser request cannot outlive this operation.
    if (signal?.aborted) {
      abort();
      await abortPromise;
    }
    await evaluation?.catch(() => {});
    if (error instanceof BrowserOperationError) throw error;
    if (signal?.aborted) {
      warmFailure(warm, 'aborted', 'meta_unavailable');
    }
    return warmFailure(warm, 'proxy_error', 'meta_unavailable');
  } finally {
    signal?.removeEventListener('abort', abort);
    warm.refreshing = false;
  }
}

async function readResponseBody(response, signal) {
  let body;
  try {
    body = await withSignal(
      typeof response.body === 'function' ? response.body() : response.text(),
      signal
    );
  } catch {
    fail('meta_unavailable');
  }
  const buffer = Buffer.isBuffer(body)
    ? body
    : Buffer.from(String(body ?? ''), 'utf8');
  if (buffer.length > RESPONSE_MAX) fail('meta_unavailable');
  return buffer.toString('utf8');
}

async function inspectRolesResponse(response, metadata, page, config, signal) {
  const status = responseStatus(response);
  if (status !== 200)
    return { ok: false, error: responseError(status, 'meta_unavailable') };
  if (!safeBrowserLocation(page.url(), config))
    return { ok: false, error: 'meta_session_expired' };
  try {
    const body = await readResponseBody(response, signal);
    validateRolesResponse(body);
    const document = parseDocument(body);
    return { ok: true, document, body, aaid: metadata.aaid };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof BrowserOperationError ? error.code : 'unknown_status',
    };
  }
}

async function inspectSearchResponse(response, signal) {
  const status = responseStatus(response);
  if (status !== 200)
    return { ok: false, error: responseError(status, 'meta_unavailable') };
  try {
    const body = await readResponseBody(response, signal);
    return { ok: true, results: parseSearchCandidates(body) };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof BrowserOperationError
          ? error.code
          : 'meta_unavailable',
    };
  }
}

function recordOnce(list, value) {
  if (!list.includes(value)) list.push(value);
}

export function operationState() {
  let resolveRoles;
  let resolveSearch;
  let resolveInviteResponse;
  let resolveInviteRequestSeen;
  return {
    rolesRequests: [],
    rolesResponses: [],
    rolesTasks: new Set(),
    rolesMultiple: false,
    rolesInvalid: false,
    rolesReady: new Promise(resolve => {
      resolveRoles = resolve;
    }),
    resolveRoles,
    rolesReadySettled: false,
    rolesResult: null,
    rolesAaid: null,
    rolesAnchorReady: false,
    typeaheadRequests: [],
    typeaheadResponses: [],
    typeaheadTasks: new Set(),
    routeTasks: new Set(),
    typeaheadPermittedCount: 0,
    typeaheadRejected: false,
    typeaheadContinueFailed: false,
    searchReady: new Promise(resolve => {
      resolveSearch = resolve;
    }),
    resolveSearch,
    searchReadySettled: false,
    searchResult: null,
    searchInput: null,
    targetCandidateUnique: false,
    targetCandidate: null,
    inviteArmed: false,
    inviteRequest: null,
    inviteRequestCount: 0,
    inviteRequestInvalid: false,
    inviteRequestDuplicate: false,
    invitePermit: null,
    inviteClosed: false,
    inviteRequestSeen: new Promise(resolve => {
      resolveInviteRequestSeen = resolve;
    }),
    resolveInviteRequestSeen,
    inviteOutcome: null,
    // Shape class only (B5 telemetry); never the body or status text.
    inviteResponseClass: 'none',
    inviteResponseController: null,
    inviteResponseSignal: null,
    inviteWriteStarted: false,
    inviteResponseCount: 0,
    inviteTasks: new Set(),
    inviteResponseReady: new Promise(resolve => {
      resolveInviteResponse = resolve;
    }),
    resolveInviteResponse,
  };
}

function inviteAnchorReady(state) {
  return (
    state.rolesAnchorReady === true &&
    state.rolesResult?.ok === true &&
    !state.rolesInvalid &&
    !state.rolesMultiple &&
    state.rolesRequests.length === 1 &&
    state.rolesResponses.length === 1 &&
    state.typeaheadPermittedCount === 1 &&
    state.typeaheadRequests.length === 1 &&
    state.typeaheadResponses.length === 1 &&
    !state.typeaheadRejected &&
    !state.typeaheadContinueFailed &&
    state.targetCandidateUnique === true
  );
}

function recordRoleRequest(state, request, metadata) {
  const existing = state.rolesRequests.find(item => item.request === request);
  if (existing) return existing;
  const item = { request, ...metadata };
  state.rolesRequests.push(item);
  if (!item.valid || state.rolesRequests.length > 1) {
    state.rolesInvalid = true;
    state.rolesAnchorReady = false;
  }
  return item;
}

function recordRoleResponse(state, response, page, config, signal) {
  const request = responseValue(response, 'request');
  const metadata = state.rolesRequests.find(item => item.request === request);
  if (!metadata) return;
  state.rolesResponses.push(response);
  if (state.rolesResponses.length > 1) {
    state.rolesMultiple = true;
    state.rolesAnchorReady = false;
  }
  const firstResponse = state.rolesResponses.length === 1;
  const task = inspectRolesResponse(
    response,
    metadata,
    page,
    config,
    signal
  ).then(result => {
    if (firstResponse && !state.rolesReadySettled) {
      state.rolesReadySettled = true;
      state.rolesResult = result;
      state.resolveRoles(result);
    }
    return result;
  });
  state.rolesTasks.add(task);
  task.finally(() => state.rolesTasks.delete(task)).catch(() => {});
}

function recordSearchResponse(state, response, signal) {
  const request = responseValue(response, 'request');
  if (!state.typeaheadRequests.includes(request)) return;
  state.typeaheadResponses.push(response);
  const firstResponse = state.typeaheadResponses.length === 1;
  const task = inspectSearchResponse(response, signal).then(result => {
    if (firstResponse && !state.searchReadySettled) {
      state.searchReadySettled = true;
      state.searchResult = result;
      state.resolveSearch(result);
    }
    return result;
  });
  state.typeaheadTasks.add(task);
  task.finally(() => state.typeaheadTasks.delete(task)).catch(() => {});
}

// The first result wins. Only a duplicate request or response replaces it.
function settleInviteOutcome(state, outcome, responseClass) {
  if (state.inviteOutcome) return;
  state.inviteOutcome = outcome;
  if (responseClass) state.inviteResponseClass = responseClass;
  state.resolveInviteResponse(outcome);
}

function replaceInviteOutcomeWithDuplicate(state) {
  state.inviteOutcome = { ok: false, error: 'invite_unknown' };
  state.inviteResponseClass = 'duplicate';
  state.resolveInviteResponse(state.inviteOutcome);
}

function unknownInvite(responseClass) {
  return { outcome: { ok: false, error: 'invite_unknown' }, responseClass };
}

// Only HTTP 200 with payload.success === true is a sent invite. Every other
// shape is classified and reported as unknown; nothing is guessed.
async function inspectInviteResponse(response, signal) {
  if (responseStatus(response) !== 200) return unknownInvite('non_200');
  let document;
  try {
    document = parseDocument(await readResponseBody(response, signal));
  } catch {
    return unknownInvite(signal?.aborted ? 'timeout' : 'malformed');
  }
  const payload = document.payload;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload))
    return unknownInvite('malformed');
  if (payload.success === true)
    return { outcome: { ok: true }, responseClass: 'success_true' };
  if (payload.success === false)
    return {
      outcome: { ok: false, error: 'invite_rejected' },
      responseClass: 'success_false',
    };
  return unknownInvite('success_missing');
}

function recordInviteResponse(state, response, signal) {
  const request = responseValue(response, 'request');
  if (!state.inviteRequest || request !== state.inviteRequest) return;
  state.inviteResponseCount += 1;
  if (state.inviteResponseCount !== 1) {
    replaceInviteOutcomeWithDuplicate(state);
    return;
  }
  // The response deadline also stops a body that stalls after its headers.
  const responseSignal = state.inviteResponseSignal
    ? AbortSignal.any([signal, state.inviteResponseSignal].filter(Boolean))
    : signal;
  const task = inspectInviteResponse(response, responseSignal).then(result => {
    settleInviteOutcome(state, result.outcome, result.responseClass);
    return result;
  });
  state.inviteTasks.add(task);
  task.finally(() => state.inviteTasks.delete(task)).catch(() => {});
}

function recordInviteRequestFailure(state, request) {
  if (!state.inviteRequest || request !== state.inviteRequest) return;
  settleInviteOutcome(
    state,
    { ok: false, error: 'invite_unknown' },
    'request_failed'
  );
}

// After this resolves, every intercepted invite POST has either marked its
// write or will hit the closed gate, so inviteWriteStarted is final.
export async function closeInviteGate(state) {
  state.inviteClosed = true;
  await Promise.allSettled([...state.routeTasks]);
}

async function inputConfirmed(input, value, signal) {
  if (!input) return false;
  try {
    const current = await withSignal(input.inputValue(), signal);
    return current === value;
  } catch {
    return false;
  }
}

function exactKeys(value, keys) {
  return (
    value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join(',') === [...keys].sort().join(',')
  );
}

function validateInvitePermitReply(reply, request) {
  const common = {
    type: 'browser_operation',
    operation: 'invite_permit',
    id: request?.id,
    request_id: request?.request_id,
    claim: request?.claim,
  };
  const commonKeys = Object.keys(common);
  if (
    exactKeys(reply, [...commonKeys, 'decision', 'status']) &&
    commonKeys.every(key => reply[key] === common[key]) &&
    ['write', 'noop'].includes(reply.decision) &&
    ['absent', 'pending'].includes(reply.status) &&
    ((reply.decision === 'write' && reply.status === 'absent') ||
      (reply.decision === 'noop' && reply.status === 'pending'))
  )
    return { decision: reply.decision, status: reply.status };
  if (
    exactKeys(reply, [...commonKeys, 'error_code']) &&
    commonKeys.every(key => reply[key] === common[key]) &&
    SAFE_ERRORS.has(reply.error_code)
  )
    return { error_code: reply.error_code };
  return null;
}

async function requestInvitePermit({
  permitInvite,
  request,
  state,
  targetId,
  username: targetUsername,
  timeoutMs,
}) {
  if (typeof permitInvite !== 'function') return null;
  // Awaited to the end, never abandoned: the manager bounds the publish with
  // timeoutMs, and an abandoned publish would block the completion publish.
  const reply = await permitInvite(
    {
      id: request.id,
      request_id: request.request_id,
      claim: request.claim,
      captured_at: state.capturedAt,
      target_id: targetId,
      username: targetUsername,
      status: 'absent',
    },
    { timeoutMs }
  );
  return validateInvitePermitReply(reply, request);
}

export async function installRoute(
  page,
  config,
  request,
  requestGuard,
  state,
  signal
) {
  if (typeof requestGuard !== 'function') fail('meta_unavailable');
  const setInviteOutcome = outcome => {
    state.inviteOutcome = outcome;
    state.resolveInviteResponse(outcome);
  };
  const handler = route => {
    const task = (async () => {
      const browserRequest = route.request();
      const url = requestUrl(browserRequest);
      const method = requestMethod(browserRequest);
      const body = requestBody(browserRequest);
      try {
        signal?.throwIfAborted();
        if (invitePath(url, config)) {
          if (
            method !== 'POST' ||
            !state.inviteArmed ||
            state.inviteRequestCount >= 1 ||
            state.inviteRequestInvalid ||
            state.inviteRequestDuplicate
          ) {
            if (state.inviteArmed && state.inviteRequestCount >= 1) {
              state.inviteRequestDuplicate = true;
              replaceInviteOutcomeWithDuplicate(state);
            }
            await route.abort('blockedbyclient');
            return;
          }
          // From here to the write marker there is no await: once the gate
          // closes, a POST is either already marked as written or blocked.
          if (state.inviteClosed || state.invitePermit !== 'write') {
            settleInviteOutcome(state, {
              ok: false,
              error: 'meta_unavailable',
              blocked: true,
            });
            await route.abort('blockedbyclient');
            return;
          }
          const metadata = inviteRequestMetadata(
            browserRequest,
            config,
            state,
            request.target_id,
            request.username
          );
          if (!metadata?.valid || !inviteAnchorReady(state)) {
            state.inviteRequestInvalid = true;
            setInviteOutcome({
              ok: false,
              error: 'invalid_selection',
              blocked: true,
            });
            await route.abort('blockedbyclient');
            return;
          }
          if (!safeBrowserLocation(page.url(), config)) {
            setInviteOutcome({
              ok: false,
              error: 'meta_session_expired',
              blocked: true,
            });
            await route.abort('blockedbyclient');
            return;
          }
          state.inviteRequestCount = 1;
          state.inviteRequest = browserRequest;
          state.inviteWriteStarted = true;
          state.resolveInviteRequestSeen();
          try {
            await route.continue();
          } catch {
            settleInviteOutcome(
              state,
              { ok: false, error: 'invite_unknown', write_started: true },
              'request_failed'
            );
          }
          return;
        }
        if (state.inviteArmed && method === 'POST') {
          if (typeaheadPath(url)) state.typeaheadRejected = true;
          await route.abort('blockedbyclient');
          return;
        }
        const roleMetadata = roleRequestMetadata(browserRequest, config);
        if (roleMetadata) {
          const role = recordRoleRequest(state, browserRequest, roleMetadata);
          if (!role.valid) {
            if (!state.rolesReadySettled) {
              state.rolesReadySettled = true;
              state.resolveRoles({ ok: false, error: 'unknown_status' });
            }
            await route.abort('blockedbyclient');
            return;
          }
          let roleAllowed = false;
          try {
            roleAllowed = requestGuard({ url, method, body }) === true;
          } catch {
            roleAllowed = false;
          }
          if (!roleAllowed) {
            if (!state.rolesReadySettled) {
              state.rolesReadySettled = true;
              state.resolveRoles({ ok: false, error: 'forbidden' });
            }
            await route.abort('blockedbyclient');
            return;
          }
          await route.continue();
          return;
        }
        if (
          ['search', 'invite'].includes(request.action) &&
          typeaheadPath(url)
        ) {
          const metadata = typeaheadRequestMetadata(
            browserRequest,
            config,
            request.username,
            state.rolesAaid
          );
          if (
            !metadata?.valid ||
            !state.rolesAnchorReady ||
            state.rolesInvalid ||
            state.rolesMultiple ||
            !safeBrowserLocation(page.url(), config) ||
            state.typeaheadRejected ||
            state.typeaheadPermittedCount >= 1 ||
            !(await inputConfirmed(
              state.searchInput,
              `@${request.username}`,
              signal
            ))
          ) {
            state.typeaheadRejected = true;
            await route.abort('blockedbyclient');
            return;
          }
          state.typeaheadPermittedCount += 1;
          recordOnce(state.typeaheadRequests, browserRequest);
          try {
            signal?.throwIfAborted();
            await route.continue();
          } catch {
            state.typeaheadContinueFailed = true;
            throw new BrowserOperationError('meta_unavailable');
          }
          return;
        }
        let allowed = false;
        try {
          allowed = requestGuard({ url, method, body }) === true;
        } catch {
          allowed = false;
        }
        if (allowed) await route.continue();
        else await route.abort('blockedbyclient');
      } catch {
        try {
          await route.abort('blockedbyclient');
        } catch {
          // Browser shutdown may race a route callback; the manager owns cleanup.
        }
      }
    })();
    state.routeTasks.add(task);
    task.finally(() => state.routeTasks.delete(task)).catch(() => {});
    return task;
  };
  await page.route('**/*', handler);
  return async () => {
    try {
      await page.unroute('**/*', handler);
    } catch {
      // The manager may already be closing the primary page.
    }
  };
}

export async function attachObservers(page, state, config, signal) {
  const onRequest = request => {
    const metadata = roleRequestMetadata(request, config);
    if (metadata) recordRoleRequest(state, request, metadata);
  };
  const onResponse = response => {
    recordRoleResponse(state, response, page, config, signal);
    recordSearchResponse(state, response, signal);
    recordInviteResponse(state, response, signal);
  };
  const onRequestFailed = request => recordInviteRequestFailure(state, request);
  page.on('request', onRequest);
  page.on('response', onResponse);
  page.on('requestfailed', onRequestFailed);
  return () => {
    page.off('request', onRequest);
    page.off('response', onResponse);
    page.off('requestfailed', onRequestFailed);
  };
}

async function waitForUnique(locator, signal) {
  const end = Date.now() + UI_WAIT_MS;
  while (Date.now() < end) {
    try {
      if ((await withSignal(locator.count(), signal)) === 1) {
        const candidate = locator.first();
        if (await withSignal(candidate.isVisible(), signal)) return candidate;
      }
    } catch {
      // The dialog can be replaced while Meta finishes rendering it.
    }
    await delay(UI_POLL_MS, signal);
  }
  return fail('meta_unavailable');
}

async function requireEnabled(locator, signal, editable = false) {
  if (!(await withSignal(locator.isEnabled(), signal)))
    fail('meta_unavailable');
  if (editable && !(await withSignal(locator.isEditable(), signal)))
    fail('meta_unavailable');
  return locator;
}

async function closeVisibleTesterDialog(page, signal) {
  const dialogs = page.getByRole('dialog');
  const count = await withSignal(dialogs.count(), signal);
  let visibleDialog = null;
  for (let index = 0; index < count; index += 1) {
    const candidate = dialogs.nth(index);
    if (await withSignal(candidate.isVisible(), signal)) {
      if (visibleDialog) fail('meta_unavailable');
      visibleDialog = candidate;
    }
  }
  if (!visibleDialog) return;
  const cancelButtons = visibleDialog.getByRole('button', {
    name: DIALOG_CANCEL_NAMES,
  });
  const cancelCount = await withSignal(cancelButtons.count(), signal);
  let close;
  if (cancelCount > 0) {
    if (cancelCount !== 1) fail('meta_unavailable');
    close = cancelButtons.first();
    if (!(await withSignal(close.isVisible(), signal)))
      fail('meta_unavailable');
    await requireEnabled(close, signal);
  } else {
    const closeButtons = visibleDialog.getByRole('button', {
      name: DIALOG_CLOSE_NAMES,
    });
    if ((await withSignal(closeButtons.count(), signal)) !== 1)
      fail('meta_unavailable');
    close = closeButtons.first();
    if (!(await withSignal(close.isVisible(), signal)))
      fail('meta_unavailable');
    await requireEnabled(close, signal);
  }
  await withSignal(close.click({ noWaitAfter: true }), signal);
  const end = Date.now() + UI_WAIT_MS;
  while (Date.now() < end) {
    try {
      if (!(await withSignal(visibleDialog.isVisible(), signal))) return;
    } catch {
      return;
    }
    await delay(UI_POLL_MS, signal);
  }
  fail('meta_unavailable');
}

function sanitizeUiTokenSnapshot(raw) {
  if (!raw || typeof raw !== 'object')
    return {
      complete: false,
      source_truncated: true,
      controls_truncated: true,
      token_button_count: 0,
      token_button_unique: false,
      token_button_visible: false,
      token_button_enabled: false,
      token_button_role: null,
    };
  const count = Number.isSafeInteger(raw.token_button_count)
    ? Math.max(0, Math.min(MAX_UI_OPTIONS, raw.token_button_count))
    : 0;
  return {
    complete:
      raw.complete === true &&
      raw.source_truncated === false &&
      raw.controls_truncated === false,
    source_truncated: raw.source_truncated !== false,
    controls_truncated: raw.controls_truncated === true,
    token_button_count: count,
    token_button_unique: raw.token_button_unique === true,
    token_button_visible: raw.token_button_visible === true,
    token_button_enabled: raw.token_button_enabled === true,
    token_button_role: raw.token_button_role === 'button' ? 'button' : null,
  };
}

async function readUiTokenButtons(dialog, targetUsername, signal) {
  try {
    const raw = await withSignal(
      dialog.evaluate(
        (element, payload) => {
          const {
            targetUsername: expectedUsername,
            maxChars,
            maxSources,
            maxControls,
          } = payload;
          const normalize = value =>
            String(value || '')
              .replace(/\s+/g, ' ')
              .trim();
          const normalizeSource = value => {
            const normalized = normalize(value);
            return {
              value: normalized.slice(0, maxChars),
              truncated: normalized.length > maxChars,
            };
          };
          const sourcesFor = node => {
            const values = [];
            let truncated = false;
            const add = value => {
              const source = normalizeSource(value);
              if (source.truncated) {
                truncated = true;
                return;
              }
              if (source.value) {
                if (values.length >= maxSources) {
                  truncated = true;
                  return;
                }
                values.push(source.value);
              }
            };
            add(node.getAttribute('aria-label'));
            add(node.getAttribute('title'));
            add(node.textContent);
            if (!truncated) {
              for (const child of node.querySelectorAll(
                '[aria-label],[title]'
              )) {
                add(child.getAttribute('aria-label'));
                add(child.getAttribute('title'));
                if (truncated) break;
              }
            }
            if (!truncated) {
              const walker = document.createTreeWalker(
                node,
                NodeFilter.SHOW_TEXT
              );
              let current = walker.nextNode();
              while (current) {
                add(current.nodeValue);
                if (truncated) break;
                current = walker.nextNode();
              }
            }
            return { values: [...new Set(values)], truncated };
          };
          const token = expectedUsername.toLowerCase();
          const tokenMatch = value =>
            value
              .split(/[^A-Za-z0-9_.]+/)
              .filter(Boolean)
              .some(item => item.toLowerCase() === token);
          const visible = node => {
            if (!node || node.getAttribute('aria-hidden') === 'true')
              return false;
            const style = window.getComputedStyle(node);
            return (
              style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              style.opacity !== '0' &&
              node.getClientRects().length > 0
            );
          };
          const enabled = node =>
            node.getAttribute('aria-disabled') !== 'true' &&
            node.disabled !== true;
          const nodes = [
            ...element.querySelectorAll('button'),
            ...element.querySelectorAll('[role="button"]'),
          ];
          const unique = [...new Set(nodes)];
          const controlsTruncated = unique.length > maxControls;
          const inspected = unique.slice(0, maxControls);
          let sourceTruncated = false;
          const matches = inspected.filter(node => {
            const sourceSet = sourcesFor(node);
            sourceTruncated ||= sourceSet.truncated;
            const nodeRole =
              String(node.getAttribute('role') || '').toLowerCase() ||
              (String(node.tagName || '').toLowerCase() === 'button'
                ? 'button'
                : null);
            return nodeRole === 'button' && sourceSet.values.some(tokenMatch);
          });
          const match = matches.length === 1 ? matches[0] : null;
          const role = match
            ? String(match.getAttribute('role') || '').toLowerCase() ||
              (String(match.tagName || '').toLowerCase() === 'button'
                ? 'button'
                : null)
            : null;
          return {
            complete: true,
            source_truncated: sourceTruncated,
            controls_truncated: controlsTruncated,
            token_button_count: matches.length,
            token_button_unique: matches.length === 1,
            token_button_visible: Boolean(match) && visible(match),
            token_button_enabled: Boolean(match) && enabled(match),
            token_button_role: role,
          };
        },
        {
          targetUsername,
          maxChars: MAX_UI_SOURCE_CHARS,
          maxSources: MAX_UI_SOURCE_VALUES,
          maxControls: MAX_UI_OPTIONS,
        }
      ),
      signal
    );
    return sanitizeUiTokenSnapshot(raw);
  } catch {
    return sanitizeUiTokenSnapshot(null);
  }
}

function sanitizeSearchOptionSnapshot(raw) {
  if (!raw || typeof raw !== 'object')
    return {
      complete: false,
      source_truncated: true,
      selection_performed: false,
      target_option_count: 0,
    };
  return {
    complete: raw.complete === true && raw.source_truncated === false,
    source_truncated: raw.source_truncated !== false,
    selection_performed: raw.selection_performed === true,
    target_option_count: Number.isSafeInteger(raw.target_option_count)
      ? Math.max(0, Math.min(MAX_UI_OPTIONS, raw.target_option_count))
      : 0,
    target_option_unique: raw.target_option_unique === true,
    target_option_visible: raw.target_option_visible === true,
    target_option_enabled: raw.target_option_enabled === true,
    linked_input_valid: raw.linked_input_valid === true,
    listbox_unique: raw.listbox_unique === true,
    listbox_visible: raw.listbox_visible === true,
    listbox_enabled: raw.listbox_enabled === true,
    options_truncated: raw.options_truncated === true,
    target_entry_id_valid: raw.target_entry_id_valid === true,
  };
}

async function selectExactSearchOption(
  input,
  targetUsername,
  targetId,
  signal
) {
  try {
    const raw = await withSignal(
      input.evaluate(
        (element, payload) => {
          const {
            targetUsername: expectedUsername,
            targetId: expectedTargetId,
            maxChars,
            maxSources,
            maxOptions,
          } = payload;
          const tag = String(element.tagName || '').toLowerCase();
          const type = String(element.getAttribute('type') || '').toLowerCase();
          const role = String(element.getAttribute('role') || '').toLowerCase();
          const linkedInputValid =
            element.isConnected === true &&
            tag === 'input' &&
            type === 'text' &&
            role === 'combobox' &&
            element.value === `@${expectedUsername}`;
          const visible = node => {
            if (!node || node.getAttribute('aria-hidden') === 'true')
              return false;
            const style = window.getComputedStyle(node);
            return (
              style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              style.opacity !== '0' &&
              node.getClientRects().length > 0
            );
          };
          const enabled = node =>
            node.getAttribute('aria-disabled') !== 'true' &&
            node.disabled !== true;
          const inputVisible = linkedInputValid && visible(element);
          const inputEnabled = linkedInputValid && enabled(element);
          const controlIds = (element.getAttribute('aria-controls') || '')
            .trim()
            .split(/\s+/)
            .filter(Boolean);
          const linkedIdUnique = controlIds.length === 1;
          const linked = linkedIdUnique
            ? document.getElementById(controlIds[0])
            : null;
          const listboxes = [...document.querySelectorAll('[role="listbox"]')];
          const listbox =
            linked &&
            linked.getAttribute('role') === 'listbox' &&
            listboxes.includes(linked)
              ? linked
              : null;
          const listboxUnique = Boolean(listbox) && listboxes.length === 1;
          const listboxVisible = listboxUnique && visible(listbox);
          const listboxEnabled = listboxUnique && enabled(listbox);
          const options = listboxUnique
            ? [...listbox.querySelectorAll('[role="option"]')]
            : [];
          const optionsTruncated = options.length > maxOptions;
          const inspected = options.slice(0, maxOptions);
          let sourceTruncated = false;
          const normalize = value =>
            String(value || '')
              .replace(/\s+/g, ' ')
              .trim();
          const normalizeSource = value => {
            const normalized = normalize(value);
            return {
              value: normalized.slice(0, maxChars),
              truncated: normalized.length > maxChars,
            };
          };
          const sourcesFor = node => {
            const values = [];
            let truncated = false;
            const add = value => {
              const source = normalizeSource(value);
              if (source.truncated) {
                truncated = true;
                return;
              }
              if (source.value) {
                if (values.length >= maxSources) {
                  truncated = true;
                  return;
                }
                values.push(source.value);
              }
            };
            add(node.getAttribute('aria-label'));
            add(node.getAttribute('title'));
            add(node.textContent);
            if (!truncated) {
              for (const child of node.querySelectorAll(
                '[aria-label],[title]'
              )) {
                add(child.getAttribute('aria-label'));
                add(child.getAttribute('title'));
                if (truncated) break;
              }
            }
            if (!truncated) {
              const walker = document.createTreeWalker(
                node,
                NodeFilter.SHOW_TEXT
              );
              let current = walker.nextNode();
              while (current) {
                add(current.nodeValue);
                if (truncated) break;
                current = walker.nextNode();
              }
            }
            return { values: [...new Set(values)], truncated };
          };
          const exactUsername = sources =>
            sources.some(
              value =>
                value === expectedUsername || value === `@${expectedUsername}`
            );
          const targetEntryIdValid = /^[0-9]{1,40}$/.test(
            String(expectedTargetId)
          );
          const matches = inspected.filter(option => {
            const sourceSet = sourcesFor(option);
            sourceTruncated ||= sourceSet.truncated;
            return exactUsername(sourceSet.values);
          });
          const option = matches.length === 1 ? matches[0] : null;
          const targetOptionVisible = Boolean(option) && visible(option);
          const targetOptionEnabled = Boolean(option) && enabled(option);
          let selectionPerformed = false;
          if (
            linkedInputValid &&
            inputVisible &&
            inputEnabled &&
            linkedIdUnique &&
            listboxUnique &&
            listboxVisible &&
            listboxEnabled &&
            !optionsTruncated &&
            !sourceTruncated &&
            targetEntryIdValid &&
            matches.length === 1 &&
            targetOptionVisible &&
            targetOptionEnabled
          ) {
            option.click();
            selectionPerformed = true;
          }
          return {
            complete: true,
            source_truncated: sourceTruncated,
            selection_performed: selectionPerformed,
            target_option_count: matches.length,
            target_option_unique: matches.length === 1,
            target_option_visible: targetOptionVisible,
            target_option_enabled: targetOptionEnabled,
            linked_input_valid: linkedInputValid,
            listbox_unique: listboxUnique,
            listbox_visible: listboxVisible,
            listbox_enabled: listboxEnabled,
            options_truncated: optionsTruncated,
            target_entry_id_valid: targetEntryIdValid,
          };
        },
        {
          targetUsername,
          targetId,
          maxChars: MAX_UI_SOURCE_CHARS,
          maxSources: MAX_UI_SOURCE_VALUES,
          maxOptions: MAX_UI_OPTIONS,
        }
      ),
      signal
    );
    return sanitizeSearchOptionSnapshot(raw);
  } catch {
    return sanitizeSearchOptionSnapshot(null);
  }
}

async function navigateRoles(page, config, signal) {
  let navigation;
  try {
    navigation = await withSignal(
      // Roles capture is response-driven. UI steps retain their own bounded
      // visibility/enabled checks after the response anchor is validated.
      page.goto(config.rolesUrl, { waitUntil: 'commit' }),
      signal
    );
  } catch (error) {
    if (error instanceof BrowserOperationError) throw error;
    fail('meta_unavailable');
  }
  if (!safeBrowserLocation(page.url(), config)) fail('meta_session_expired');
  const status = responseStatus(navigation);
  if (status && status !== 200) fail(responseError(status, 'meta_unavailable'));
}

async function captureRoles(state, page, config, signal, warmMetaPage = null) {
  let result;
  try {
    result = await withSignal(state.rolesReady, signal);
  } catch (error) {
    if (warmMetaPage) invalidateWarmMetaPage(warmMetaPage, 'aborted');
    throw error;
  }
  if (
    state.rolesRequests.length !== 1 ||
    state.rolesResponses.length !== 1 ||
    state.rolesMultiple ||
    state.rolesInvalid
  ) {
    if (warmMetaPage)
      invalidateWarmMetaPage(warmMetaPage, 'roles_response_invalid');
    fail(result?.error || 'unknown_status');
  }
  if (!result?.ok) {
    if (warmMetaPage)
      invalidateWarmMetaPage(
        warmMetaPage,
        result?.error === 'meta_session_expired'
          ? 'csrf_expired'
          : 'roles_response_invalid'
      );
    fail(result?.error || 'unknown_status');
  }
  state.rolesAaid = result.aaid;
  state.rolesAnchorReady = numeric(state.rolesAaid);
  if (!state.rolesAnchorReady) {
    if (warmMetaPage)
      invalidateWarmMetaPage(warmMetaPage, 'roles_response_invalid');
    fail('unknown_status');
  }
  if (!safeBrowserLocation(page.url(), config)) {
    if (warmMetaPage) invalidateWarmMetaPage(warmMetaPage, 'page_changed');
    fail('meta_session_expired');
  }
  if (warmMetaPage) {
    acceptFreshRolesResponse(warmMetaPage, {
      page,
      configuration: config,
      request: state.rolesRequests[0].request,
      response: state.rolesResponses[0],
      body: result.body,
      source: 'same_page_refresh',
    });
  }
  return result.document;
}

async function openTesterSearch({
  page,
  config,
  request,
  state,
  signal,
  navigate,
  warmMetaPage = null,
}) {
  let rolesDocument = null;
  if (navigate) {
    const refreshWarm = warmRefreshRequired(warmMetaPage, page, config);
    if (refreshWarm) {
      state.diagnosticPhase = 'roles_refresh';
      await refreshWarmMetaPage(warmMetaPage, {
        page,
        configuration: config,
        signal,
      });
    } else {
      state.diagnosticPhase = 'roles_navigation';
      await navigateRoles(page, config, signal);
    }
    state.diagnosticPhase = 'roles_capture';
    rolesDocument = await captureRoles(
      state,
      page,
      config,
      signal,
      warmMetaPage
    );
  }
  if (warmMetaPage) {
    state.diagnosticPhase = 'tester_dialog_reset';
    await closeVisibleTesterDialog(page, signal);
  }
  state.diagnosticPhase = 'add_people_button';
  const add = await waitForUnique(
    page.getByRole('button', { name: /^(?:Add people|Adicionar pessoas)$/i }),
    signal
  );
  await requireEnabled(add, signal);
  await withSignal(add.click({ noWaitAfter: true }), signal);
  state.diagnosticPhase = 'tester_dialog';
  const dialog = await waitForUnique(page.getByRole('dialog'), signal);
  state.diagnosticPhase = 'tester_role';
  const role = await waitForUnique(
    dialog.getByRole('radio', {
      name: /^(?:Instagram tester|Instagram testers|Testador do Instagram|Testadores do Instagram)$/i,
    }),
    signal
  );
  await requireEnabled(role, signal);
  await withSignal(role.check(), signal);
  if (!(await withSignal(role.isChecked(), signal))) fail('meta_unavailable');
  state.diagnosticPhase = 'search_input';
  const input = await waitForUnique(dialog.getByRole('combobox'), signal);
  state.searchInput = await requireEnabled(input, signal, true);
  await withSignal(state.searchInput.fill(`@${request.username}`), signal);
  if (
    !(await inputConfirmed(state.searchInput, `@${request.username}`, signal))
  )
    fail('meta_unavailable');
  state.diagnosticPhase = 'typeahead_response';
  const result = await withSignal(state.searchReady, signal);
  if (!safeBrowserLocation(page.url(), config)) fail('meta_session_expired');
  if (
    state.typeaheadPermittedCount !== 1 ||
    state.typeaheadRequests.length !== 1 ||
    state.typeaheadResponses.length !== 1 ||
    state.typeaheadRejected ||
    state.typeaheadContinueFailed ||
    state.rolesInvalid ||
    state.rolesMultiple ||
    state.rolesRequests.length !== 1 ||
    state.rolesResponses.length !== 1
  )
    fail(result?.error || 'meta_unavailable');
  if (!result?.ok) fail(result?.error || 'meta_unavailable');
  return { results: result.results, dialog, rolesDocument };
}

// Only the exact username the actor typed gets a status, so a search exposes
// no more than the single status read it replaces. An unreadable roster
// leaves every status unknown (null) and the search still succeeds.
function searchStatuses(results, rolesDocument, request) {
  let statuses;
  try {
    statuses = rolesStatusMap(rolesDocument);
  } catch {
    statuses = null;
  }
  return results.map(candidate => ({
    ...candidate,
    tester_status:
      statuses && candidate.username === request.username
        ? (statuses.get(candidate.id) ?? 'absent')
        : null,
  }));
}

async function performSearch({
  page,
  config,
  request,
  state,
  signal,
  warmMetaPage,
  searchStatus,
}) {
  const result = await openTesterSearch({
    page,
    config,
    request,
    state,
    signal,
    navigate: true,
    warmMetaPage,
  });
  if (!searchStatus) return result.results;
  return searchStatuses(result.results, result.rolesDocument, request);
}

function requireUniqueInviteCandidate(results, request, state) {
  const matches = results.filter(
    candidate =>
      candidate.id === request.target_id &&
      candidate.username === request.username
  );
  if (matches.length !== 1) fail('invalid_selection');
  state.targetCandidate = matches[0];
  state.targetCandidateUnique = true;
  return matches[0];
}

function remainingMs(deadlineAt, now) {
  return deadlineAt - operationNow(now);
}

// Resolves with the first settled promise, or after ms; the timer never
// outlives the wait.
async function waitAtMost(promises, ms, signal) {
  let timer;
  const timeout = new Promise(resolve => {
    timer = setTimeout(resolve, Math.max(0, ms));
  });
  try {
    await withSignal(Promise.race([...promises, timeout]), signal);
  } finally {
    clearTimeout(timer);
  }
}

async function requestPermitBeforeClick({
  page,
  config,
  request,
  state,
  permitInvite,
  deadlineAt,
  now,
}) {
  const permitBudget = Math.min(
    INVITE_PERMIT_MAX_MS,
    remainingMs(deadlineAt, now) - INVITE_AFTER_PERMIT_MS
  );
  if (!(permitBudget > 0)) fail('meta_unavailable');
  let permit;
  try {
    permit = await requestInvitePermit({
      permitInvite,
      request,
      state,
      targetId: request.target_id,
      username: request.username,
      timeoutMs: permitBudget,
    });
  } catch {
    permit = null;
  }
  if (!permit) fail('meta_unavailable');
  if (permit.error_code) fail(permit.error_code);
  if (permit.decision === 'noop') return permit;
  state.invitePermit = 'write';
  // The permit marks Rails' claim; any failure before the click is reported
  // with write_started:false, so Rails releases that marker.
  if (!inviteAnchorReady(state)) fail('invalid_selection');
  if (!safeBrowserLocation(page.url(), config)) fail('meta_session_expired');
  if (remainingMs(deadlineAt, now) < INVITE_AFTER_PERMIT_MS)
    fail('meta_unavailable');
  return permit;
}

async function waitForInviteRequest(state, signal) {
  await waitAtMost(
    [state.inviteRequestSeen, state.inviteResponseReady],
    INVITE_REQUEST_WAIT_MS,
    signal
  );
  if (state.inviteWriteStarted) return;
  await closeInviteGate(state);
  if (state.inviteWriteStarted) return;
  fail(
    state.inviteOutcome?.blocked
      ? state.inviteOutcome.error
      : 'meta_unavailable'
  );
}

async function waitForInviteResponse(state, signal, deadlineAt, now) {
  const responseWait = Math.min(
    INVITE_RESPONSE_TIMEOUT_MS,
    remainingMs(deadlineAt, now)
  );
  const timer = setTimeout(
    () => state.inviteResponseController.abort(new Error('invite_timeout')),
    Math.max(0, responseWait)
  );
  try {
    await withSignal(
      state.inviteResponseReady,
      AbortSignal.any([signal, state.inviteResponseSignal].filter(Boolean))
    );
  } catch (error) {
    if (signal?.aborted) throw error;
    settleInviteOutcome(
      state,
      { ok: false, error: 'invite_unknown' },
      'timeout'
    );
  } finally {
    clearTimeout(timer);
  }
  return state.inviteOutcome;
}

async function performInvite({
  page,
  config,
  request,
  state,
  signal,
  permitInvite,
  deadlineAt,
  now,
  warmMetaPage = null,
}) {
  const { results, dialog } = await openTesterSearch({
    page,
    config,
    request,
    state,
    signal,
    navigate: false,
    warmMetaPage,
  });
  requireUniqueInviteCandidate(results, request, state);
  const baseline = await readUiTokenButtons(dialog, request.username, signal);
  if (
    !baseline.complete ||
    baseline.source_truncated ||
    baseline.token_button_count !== 0
  ) {
    // A reused page that is not clean (for example a token left selected by
    // an earlier operation) recovers with a cold navigation on the next op.
    if (warmMetaPage) invalidateWarmMetaPage(warmMetaPage, 'page_changed');
    fail('invalid_selection');
  }
  const option = await selectExactSearchOption(
    state.searchInput,
    request.username,
    request.target_id,
    signal
  );
  if (
    !option.complete ||
    option.source_truncated ||
    option.options_truncated ||
    !option.linked_input_valid ||
    !option.listbox_unique ||
    !option.listbox_visible ||
    !option.listbox_enabled ||
    !option.target_entry_id_valid ||
    !option.target_option_unique ||
    !option.target_option_visible ||
    !option.target_option_enabled ||
    !option.selection_performed
  )
    fail('invalid_selection');
  await delay(UI_POLL_MS, signal);
  if (
    (await withSignal(dialog.count(), signal)) !== 1 ||
    !(await withSignal(dialog.isVisible(), signal))
  )
    fail('invalid_selection');
  const selected = await readUiTokenButtons(dialog, request.username, signal);
  if (
    !selected.complete ||
    selected.source_truncated ||
    selected.token_button_count !== 1 ||
    !selected.token_button_unique ||
    !selected.token_button_visible ||
    !selected.token_button_enabled ||
    selected.token_button_role !== 'button'
  )
    fail('invalid_selection');
  const role = await waitForUnique(
    dialog.getByRole('radio', {
      name: /^(?:Instagram tester|Instagram testers|Testador do Instagram|Testadores do Instagram)$/i,
    }),
    signal
  );
  const roleChecked =
    (await withSignal(role.isVisible(), signal)) &&
    (await withSignal(role.isEnabled(), signal)) &&
    (await withSignal(role.isChecked(), signal));
  if (!roleChecked) fail('invalid_selection');
  const addButton = await waitForUnique(
    dialog.getByRole('button', { name: /^(?:Add|Adicionar)$/i }),
    signal
  );
  await requireEnabled(addButton, signal);
  if (!inviteAnchorReady(state)) fail('invalid_selection');
  const permit = await requestPermitBeforeClick({
    page,
    config,
    request,
    state,
    permitInvite,
    deadlineAt,
    now,
  });
  if (permit.decision === 'noop')
    return {
      target_id: request.target_id,
      status: 'pending',
      invited: false,
      write_started: false,
    };
  state.inviteResponseController = new AbortController();
  state.inviteResponseSignal = state.inviteResponseController.signal;
  state.inviteArmed = true;
  try {
    await addButton.click({
      noWaitAfter: true,
      timeout: INVITE_CLICK_TIMEOUT_MS,
    });
  } catch {
    // A click error never decides the outcome; the request wait does.
  }
  await waitForInviteRequest(state, signal);
  const outcome = await waitForInviteResponse(state, signal, deadlineAt, now);
  if (outcome?.error) fail(outcome.error);
  if (
    outcome?.ok !== true ||
    !state.inviteWriteStarted ||
    state.inviteRequestCount !== 1
  )
    fail('invite_unknown');
  await delay(UI_POLL_MS, signal);
  if (state.inviteResponseCount !== 1) fail('invite_unknown');
  return {
    target_id: request.target_id,
    status: 'pending',
    invited: true,
    write_started: true,
  };
}

async function performStatus({
  page,
  config,
  request,
  state,
  signal,
  warmMetaPage = null,
  warmInvite = false,
}) {
  // Without the warm-invite flag an invite always reads roles cold.
  const reuseWarm = request.action !== 'invite' || warmInvite;
  const documentPromise = (async () => {
    const refreshWarm =
      reuseWarm && warmRefreshRequired(warmMetaPage, page, config);
    if (refreshWarm) {
      state.diagnosticPhase = 'roles_refresh';
      await refreshWarmMetaPage(warmMetaPage, {
        page,
        configuration: config,
        signal,
      });
    } else {
      if (
        !reuseWarm &&
        warmMetaPage &&
        !warmMetaPage.valid &&
        !warmCanRecoverCold(warmMetaPage, page, config)
      )
        fail(warmInvalidationError(warmMetaPage));
      state.diagnosticPhase = 'roles_navigation';
      await navigateRoles(page, config, signal);
    }
    state.diagnosticPhase = 'roles_capture';
    return captureRoles(state, page, config, signal, warmMetaPage);
  })();
  const document = await documentPromise;
  state.diagnosticPhase = 'roles_status';
  if (state.rolesRequests.length !== 1 || state.rolesResponses.length !== 1)
    fail('unknown_status');
  return parseRolesStatus(JSON.stringify(document), request.target_id);
}

export async function executeBrowserOperation({
  page,
  configuration,
  request,
  signal,
  requestGuard,
  permitInvite,
  onDiagnostic,
  warmMetaPage = null,
  searchStatus = false,
  warmInvite = false,
  deadlineAt,
  now = Date.now,
} = {}) {
  const started = baseEnvelope(request, now);
  const executionDeadline = Number.isFinite(deadlineAt)
    ? deadlineAt
    : operationNow(now) + DEFAULT_EXECUTION_BUDGET_MS;
  let removeRoute;
  let removeObservers;
  const state = operationState();
  try {
    state.diagnosticPhase = 'configuration_validation';
    validateConfiguration(configuration);
    state.diagnosticPhase = 'request_validation';
    validateRequest(request, configuration);
    state.capturedAt = timestamp(now);
    if (
      !page ||
      typeof page.route !== 'function' ||
      typeof page.goto !== 'function'
    )
      fail('meta_unavailable');
    state.diagnosticPhase = 'observers';
    removeObservers = await attachObservers(page, state, configuration, signal);
    state.diagnosticPhase = 'request_routes';
    removeRoute = await installRoute(
      page,
      configuration,
      request,
      requestGuard,
      state,
      signal
    );
    if (request.action === 'search') {
      const results = await performSearch({
        page,
        config: configuration,
        request,
        state,
        signal,
        warmMetaPage,
        searchStatus: searchStatus === true,
      });
      return successEnvelope(request, { results }, now);
    }
    const status = await performStatus({
      page,
      config: configuration,
      request,
      state,
      signal,
      warmMetaPage,
      warmInvite: warmInvite === true,
    });
    if (request.action === 'invite') {
      if (status !== 'absent')
        return successEnvelope(
          request,
          {
            target_id: request.target_id,
            status,
            invited: false,
            write_started: false,
          },
          now
        );
      state.diagnosticPhase = 'invite_execution';
      const result = await performInvite({
        page,
        config: configuration,
        request,
        state,
        signal,
        permitInvite,
        deadlineAt: executionDeadline,
        now,
        warmMetaPage: warmInvite === true ? warmMetaPage : null,
      });
      return successEnvelope(request, result, now);
    }
    return successEnvelope(
      request,
      { target_id: request.target_id, status },
      now
    );
  } catch (error) {
    // write_started is read only after the gate closes, so a POST still in
    // its route callback can never be reported as unsent.
    if (request?.action === 'invite') await closeInviteGate(state);
    const writeStarted = state.inviteWriteStarted === true;
    let code = SAFE_ERRORS.has(error?.code) ? error.code : 'meta_unavailable';
    // After a write only Meta's explicit rejection is a known outcome.
    if (writeStarted && code !== 'invite_rejected') code = 'invite_unknown';
    try {
      onDiagnostic?.({
        event: 'instagram_browser_operation_executor_failed',
        phase: state.diagnosticPhase,
        action: ACTIONS.has(request?.action) ? request.action : 'invalid',
        error_code: code,
        roles_request_count: state.rolesRequests.length,
        roles_response_count: state.rolesResponses.length,
        typeahead_request_count: state.typeaheadRequests.length,
        typeahead_response_count: state.typeaheadResponses.length,
        typeahead_rejected: state.typeaheadRejected === true,
        typeahead_continue_failed: state.typeaheadContinueFailed === true,
      });
    } catch {
      // Diagnostics must not change the terminal observation.
    }
    return {
      ...started,
      ...(request?.action === 'invite'
        ? {
            target_id: request?.target_id ?? null,
            write_started: writeStarted,
          }
        : {}),
      error_code: code,
    };
  } finally {
    if (removeRoute) await removeRoute();
    if (removeObservers) removeObservers();
    state.inviteResponseController?.abort(new Error('operation_finished'));
    // Route callbacks may still be writing, so they are awaited in full. The
    // observer tasks only read and are bounded.
    await Promise.allSettled([...state.routeTasks]);
    await waitAtMost(
      [
        Promise.allSettled([
          ...state.rolesTasks,
          ...state.typeaheadTasks,
          ...state.inviteTasks,
        ]),
      ],
      TASK_SETTLE_MS
    );
  }
}
