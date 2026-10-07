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

export function parseRolesStatus(body, targetId) {
  if (!numeric(targetId)) fail('invalid_selection');
  const document = parseDocument(body);
  const container = document.data?.get_app_roles;
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
        !['PENDING', 'CONFIRMED'].includes(user.status)
      )
        fail('unknown_status');
      const values = statuses.get(user.id) || new Set();
      values.add(user.status);
      statuses.set(user.id, values);
    }
  }
  if ([...statuses.values()].some(values => values.size > 1))
    fail('unknown_status');
  const status = statuses.get(targetId);
  if (!status) return 'absent';
  const value = [...status][0];
  if (value === 'PENDING') return 'pending';
  if (value === 'CONFIRMED') return 'accepted';
  return fail('unknown_status');
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
    return { ok: true, document, aaid: metadata.aaid };
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

function operationState() {
  let resolveRoles;
  let resolveSearch;
  let resolveInviteResponse;
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
    invitePermitPending: false,
    inviteOutcome: null,
    inviteWriteStarted: false,
    inviteResponse: null,
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

async function inspectInviteResponse(response, signal) {
  if (responseStatus(response) !== 200)
    return { ok: false, error: 'invite_unknown' };
  try {
    const body = await readResponseBody(response, signal);
    const document = parseDocument(body);
    const payload = document.payload;
    if (!payload || typeof payload !== 'object' || Array.isArray(payload))
      return { ok: false, error: 'invite_unknown' };
    if (payload.success === true) return { ok: true };
    if (payload.success === false)
      return { ok: false, error: 'invite_rejected' };
    return { ok: false, error: 'invite_unknown' };
  } catch {
    return { ok: false, error: 'invite_unknown' };
  }
}

function recordInviteResponse(state, response, signal) {
  const request = responseValue(response, 'request');
  if (!state.inviteRequest || request !== state.inviteRequest) return;
  state.inviteResponseCount += 1;
  if (state.inviteResponseCount !== 1) {
    state.inviteResponse = { ok: false, error: 'invite_unknown' };
    state.inviteOutcome = state.inviteResponse;
    state.resolveInviteResponse(state.inviteResponse);
    return;
  }
  const task = inspectInviteResponse(response, signal).then(result => {
    state.inviteResponse = result;
    if (!state.inviteOutcome) {
      state.inviteOutcome = result;
      state.resolveInviteResponse(result);
    }
    return result;
  });
  state.inviteTasks.add(task);
  task.finally(() => state.inviteTasks.delete(task)).catch(() => {});
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
  signal,
}) {
  if (typeof permitInvite !== 'function') return null;
  const reply = await withSignal(
    permitInvite({
      id: request.id,
      request_id: request.request_id,
      claim: request.claim,
      captured_at: state.capturedAt,
      target_id: targetId,
      username: targetUsername,
      status: 'absent',
    }),
    signal
  );
  return validateInvitePermitReply(reply, request);
}

async function installRoute(
  page,
  config,
  request,
  requestGuard,
  state,
  signal,
  permitInvite
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
              setInviteOutcome({ ok: false, error: 'invite_unknown' });
            }
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
            setInviteOutcome({ ok: false, error: 'invite_unknown' });
            await route.abort('blockedbyclient');
            return;
          }
          state.inviteRequestCount += 1;
          state.inviteRequest = browserRequest;
          state.invitePermitPending = true;
          let permit;
          try {
            permit = await requestInvitePermit({
              permitInvite,
              request,
              state,
              targetId: request.target_id,
              username: request.username,
              signal,
            });
          } catch {
            permit = null;
          } finally {
            state.invitePermitPending = false;
          }
          if (!permit) {
            setInviteOutcome({ ok: false, error: 'invite_unknown' });
            await route.abort('blockedbyclient');
            return;
          }
          if (permit.error_code) {
            setInviteOutcome({ ok: false, error: permit.error_code });
            await route.abort('blockedbyclient');
            return;
          }
          if (permit.decision === 'noop') {
            setInviteOutcome({
              ok: false,
              noop: true,
              status: 'pending',
              invited: false,
              write_started: false,
            });
            await route.abort('blockedbyclient');
            return;
          }
          if (
            !inviteAnchorReady(state) ||
            !safeBrowserLocation(page.url(), config) ||
            state.inviteRequest !== browserRequest ||
            state.inviteRequestCount !== 1
          ) {
            setInviteOutcome({ ok: false, error: 'invite_unknown' });
            await route.abort('blockedbyclient');
            return;
          }
          signal?.throwIfAborted();
          state.inviteWriteStarted = true;
          try {
            await route.continue();
          } catch {
            setInviteOutcome({
              ok: false,
              error: 'invite_unknown',
              write_started: true,
            });
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

async function attachObservers(page, state, config, signal) {
  const onRequest = request => {
    const metadata = roleRequestMetadata(request, config);
    if (metadata) recordRoleRequest(state, request, metadata);
  };
  const onResponse = response => {
    recordRoleResponse(state, response, page, config, signal);
    recordSearchResponse(state, response, signal);
    recordInviteResponse(state, response, signal);
  };
  page.on('request', onRequest);
  page.on('response', onResponse);
  return () => {
    page.off('request', onRequest);
    page.off('response', onResponse);
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
      page.goto(config.rolesUrl, { waitUntil: 'domcontentloaded' }),
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

async function captureRoles(state, page, config, signal) {
  const result = await withSignal(state.rolesReady, signal);
  if (
    state.rolesRequests.length !== 1 ||
    state.rolesResponses.length !== 1 ||
    state.rolesMultiple ||
    state.rolesInvalid
  )
    fail(result?.error || 'unknown_status');
  if (!result?.ok) fail(result?.error || 'unknown_status');
  state.rolesAaid = result.aaid;
  state.rolesAnchorReady = numeric(state.rolesAaid);
  if (!state.rolesAnchorReady) fail('unknown_status');
  if (!safeBrowserLocation(page.url(), config)) fail('meta_session_expired');
  return result.document;
}

async function openTesterSearch({
  page,
  config,
  request,
  state,
  signal,
  navigate,
}) {
  if (navigate) {
    await navigateRoles(page, config, signal);
    await captureRoles(state, page, config, signal);
  }
  const add = await waitForUnique(
    page.getByRole('button', { name: /^(?:Add people|Adicionar pessoas)$/i }),
    signal
  );
  await requireEnabled(add, signal);
  await withSignal(add.click({ noWaitAfter: true }), signal);
  const dialog = await waitForUnique(page.getByRole('dialog'), signal);
  const role = await waitForUnique(
    dialog.getByRole('radio', {
      name: /^(?:Instagram tester|Instagram testers|Testador do Instagram|Testadores do Instagram)$/i,
    }),
    signal
  );
  await requireEnabled(role, signal);
  await withSignal(role.check(), signal);
  if (!(await withSignal(role.isChecked(), signal))) fail('meta_unavailable');
  const input = await waitForUnique(dialog.getByRole('combobox'), signal);
  state.searchInput = await requireEnabled(input, signal, true);
  await withSignal(state.searchInput.fill(`@${request.username}`), signal);
  if (
    !(await inputConfirmed(state.searchInput, `@${request.username}`, signal))
  )
    fail('meta_unavailable');
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
  return { results: result.results, dialog };
}

async function performSearch({ page, config, request, state, signal }) {
  const result = await openTesterSearch({
    page,
    config,
    request,
    state,
    signal,
    navigate: true,
  });
  return result.results;
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

async function waitForInviteOutcome(state, signal) {
  if (state.inviteOutcome) return state.inviteOutcome;
  return withSignal(
    Promise.race([
      state.inviteResponseReady,
      delay(UI_WAIT_MS, signal).then(() => ({
        ok: false,
        error: 'invite_unknown',
      })),
    ]),
    signal
  );
}

async function performInvite({ page, config, request, state, signal }) {
  const { results, dialog } = await openTesterSearch({
    page,
    config,
    request,
    state,
    signal,
    navigate: false,
  });
  requireUniqueInviteCandidate(results, request, state);
  const baseline = await readUiTokenButtons(dialog, request.username, signal);
  if (
    !baseline.complete ||
    baseline.source_truncated ||
    baseline.token_button_count !== 0
  )
    fail('invalid_selection');
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
  state.inviteArmed = true;
  try {
    await withSignal(addButton.click({ noWaitAfter: true }), signal);
  } catch {
    if (!state.inviteOutcome) fail('invite_unknown');
  }
  const outcome = await waitForInviteOutcome(state, signal);
  if (outcome?.noop === true && outcome.status === 'pending')
    return {
      target_id: request.target_id,
      status: 'pending',
      invited: false,
      write_started: false,
    };
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

async function performStatus({ page, config, request, state, signal }) {
  const documentPromise = (async () => {
    await navigateRoles(page, config, signal);
    return captureRoles(state, page, config, signal);
  })();
  const document = await documentPromise;
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
  now = Date.now,
} = {}) {
  const started = baseEnvelope(request, now);
  let removeRoute;
  let removeObservers;
  const state = operationState();
  try {
    validateConfiguration(configuration);
    validateRequest(request, configuration);
    state.capturedAt = timestamp(now);
    if (
      !page ||
      typeof page.route !== 'function' ||
      typeof page.goto !== 'function'
    )
      fail('meta_unavailable');
    removeObservers = await attachObservers(page, state, configuration, signal);
    removeRoute = await installRoute(
      page,
      configuration,
      request,
      requestGuard,
      state,
      signal,
      permitInvite
    );
    if (request.action === 'search') {
      const results = await performSearch({
        page,
        config: configuration,
        request,
        state,
        signal,
      });
      return successEnvelope(request, { results }, now);
    }
    const status = await performStatus({
      page,
      config: configuration,
      request,
      state,
      signal,
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
      const result = await performInvite({
        page,
        config: configuration,
        request,
        state,
        signal,
      });
      return successEnvelope(request, result, now);
    }
    return successEnvelope(
      request,
      { target_id: request.target_id, status },
      now
    );
  } catch (error) {
    const code = SAFE_ERRORS.has(error?.code) ? error.code : 'meta_unavailable';
    return {
      ...started,
      ...(request?.action === 'invite'
        ? {
            target_id: request?.target_id ?? null,
            write_started: state.inviteWriteStarted === true,
          }
        : {}),
      error_code: code,
    };
  } finally {
    if (removeRoute) await removeRoute();
    if (removeObservers) removeObservers();
    await Promise.allSettled([
      ...state.rolesTasks,
      ...state.typeaheadTasks,
      ...state.inviteTasks,
      ...state.routeTasks,
    ]);
  }
}
