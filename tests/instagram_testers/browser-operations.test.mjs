import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import * as operations from '../../scripts/instagram_testers/browser-operations.mjs';

const config = Object.freeze({
  appId: '10001',
  businessId: '10002',
  docId: '10003',
  adminId: '12345',
  rolesUrl:
    'https://developers.facebook.com/apps/10001/roles/roles/?business_id=10002',
});
const TARGET_ID = '178414000000000001';
const USERNAME = 'latency.synthetic';
const ROLES_AAID = '9000001';
const INVITE_URL =
  'https://developers.facebook.com/apps/10001/async/instagram/roles/add/';
const request = Object.freeze({
  action: 'invite',
  id: '33333333-3333-4333-8333-333333333333',
  request_id: '66666666-6666-4666-8666-666666666666',
  claim: '99999999-9999-4999-8999-999999999999',
  app_id: config.appId,
  username: USERNAME,
  target_id: TARGET_ID,
});

function inviteBody() {
  return new URLSearchParams([
    ['__aaid', ROLES_AAID],
    ['__bid', config.businessId],
    ['__user', config.adminId],
    ['__a', '1'],
    ['__req', '1'],
    ['__hs', '1'],
    ['dpr', '1'],
    ['__ccg', '1'],
    ['__rev', '1'],
    ['__s', ''],
    ['__hsi', '1'],
    ['__dyn', '1'],
    ['fb_dtsg', 'synthetic_fb_dtsg'],
    ['jazoest', 'synthetic_jazoest'],
    ['lsd', 'synthetic_lsd'],
    ['qpl_active_flow_ids', ''],
    ['role', 'instagram testers'],
    ['user_id_or_vanitys[0]', TARGET_ID],
    ['reload_on_success', 'false'],
  ]).toString();
}

function invitePost() {
  const body = inviteBody();
  return { url: () => INVITE_URL, method: () => 'POST', postData: () => body };
}

// Everything the existing guards require, so only the new gate can block.
function readyState() {
  const state = operations.operationState();
  state.rolesAnchorReady = true;
  state.rolesResult = { ok: true };
  state.rolesAaid = ROLES_AAID;
  state.rolesRequests.push({ request: {}, valid: true, aaid: ROLES_AAID });
  state.rolesResponses.push({});
  state.typeaheadPermittedCount = 1;
  state.typeaheadRequests.push({});
  state.typeaheadResponses.push({});
  state.targetCandidateUnique = true;
  state.inviteArmed = true;
  return state;
}

function fakePage() {
  const page = new EventEmitter();
  page.url = () => config.rolesUrl;
  page.route = async (_pattern, handler) => {
    page.routeHandler = handler;
  };
  page.unroute = async () => {};
  return page;
}

function fakeRoute(browserRequest, { continueDelayMs = 0 } = {}) {
  const calls = { abort: 0, continue: 0 };
  return {
    calls,
    request: () => browserRequest,
    abort: async () => {
      calls.abort += 1;
    },
    continue: async () => {
      if (continueDelayMs) await delay(continueDelayMs);
      calls.continue += 1;
    },
  };
}

async function routedPage(state) {
  const page = fakePage();
  await operations.installRoute(
    page,
    config,
    request,
    () => true,
    state,
    undefined
  );
  return page;
}

function inviteResponse(browserRequest, status, body) {
  return {
    request: () => browserRequest,
    status: () => status,
    text: async () => body,
  };
}

test('gate_blocks_armed_post_after_close', async () => {
  const state = readyState();
  state.invitePermit = 'write';
  state.inviteClosed = true;
  const page = await routedPage(state);
  const route = fakeRoute(invitePost());

  await page.routeHandler(route);

  assert.equal(route.calls.abort, 1);
  assert.equal(route.calls.continue, 0);
  assert.equal(state.inviteWriteStarted, false);
  assert.equal(state.inviteRequestCount, 0);
  // The gate runs before the metadata guards.
  assert.equal(state.inviteRequestInvalid, false);
  assert.deepEqual(state.inviteOutcome, {
    ok: false,
    error: 'meta_unavailable',
    blocked: true,
  });
});

test('gate_blocks_armed_post_without_permit', async () => {
  const state = readyState();
  const page = await routedPage(state);
  const route = fakeRoute(invitePost());

  await page.routeHandler(route);

  assert.equal(route.calls.abort, 1);
  assert.equal(route.calls.continue, 0);
  assert.equal(state.inviteWriteStarted, false);
  assert.equal(state.inviteRequestInvalid, false);
  assert.equal(state.inviteOutcome?.error, 'meta_unavailable');
  assert.equal(state.inviteOutcome?.blocked, true);
});

test('open gate continues exactly one valid post without awaiting a permit', async () => {
  const state = readyState();
  state.invitePermit = 'write';
  const page = await routedPage(state);
  const route = fakeRoute(invitePost());

  const task = page.routeHandler(route);
  // No await may sit between the gate and the write marker.
  assert.equal(state.inviteWriteStarted, true);
  await task;
  await state.inviteRequestSeen;

  assert.equal(route.calls.continue, 1);
  assert.equal(route.calls.abort, 0);
  assert.equal(state.inviteRequestCount, 1);
  assert.equal(state.inviteOutcome, null);
});

test('close_waits_for_inflight_route_task', async () => {
  const state = readyState();
  state.invitePermit = 'write';
  const page = await routedPage(state);
  const route = fakeRoute(invitePost(), { continueDelayMs: 200 });

  page.routeHandler(route);
  await operations.closeInviteGate(state);

  assert.equal(state.inviteClosed, true);
  assert.equal(route.calls.continue, 1);
  assert.equal(state.inviteWriteStarted, true);
  assert.equal(state.routeTasks.size, 0);
});

test('a post that arrives after the gate closes is never written', async () => {
  const state = readyState();
  state.invitePermit = 'write';
  const page = await routedPage(state);
  await operations.closeInviteGate(state);
  const route = fakeRoute(invitePost());

  await page.routeHandler(route);

  assert.equal(route.calls.continue, 0);
  assert.equal(state.inviteWriteStarted, false);
});

test('a second post after the write is a duplicate and unknown', async () => {
  const state = readyState();
  state.invitePermit = 'write';
  const page = await routedPage(state);
  const first = fakeRoute(invitePost());
  const second = fakeRoute(invitePost());

  await page.routeHandler(first);
  await page.routeHandler(second);

  assert.equal(first.calls.continue, 1);
  assert.equal(second.calls.continue, 0);
  assert.equal(second.calls.abort, 1);
  assert.equal(state.inviteOutcome?.error, 'invite_unknown');
  assert.equal(state.inviteResponseClass, 'duplicate');
});

test('requestfailed_after_success_keeps_success', async () => {
  const state = operations.operationState();
  const page = fakePage();
  const browserRequest = invitePost();
  state.inviteRequest = browserRequest;
  await operations.attachObservers(page, state, config, undefined);

  page.emit(
    'response',
    inviteResponse(browserRequest, 200, '{"payload":{"success":true}}')
  );
  await state.inviteResponseReady;
  page.emit('requestfailed', browserRequest);

  assert.deepEqual(state.inviteOutcome, { ok: true });
  assert.equal(state.inviteResponseClass, 'success_true');
});

test('requestfailed before any response is unknown and keeps the first result', async () => {
  const state = operations.operationState();
  const page = fakePage();
  const browserRequest = invitePost();
  state.inviteRequest = browserRequest;
  await operations.attachObservers(page, state, config, undefined);

  page.emit('requestfailed', invitePost());
  assert.equal(state.inviteOutcome, null);
  page.emit('requestfailed', browserRequest);
  page.emit(
    'response',
    inviteResponse(browserRequest, 200, '{"payload":{"success":true}}')
  );
  await Promise.allSettled([...state.inviteTasks]);

  assert.equal(state.inviteOutcome?.error, 'invite_unknown');
  assert.equal(state.inviteResponseClass, 'request_failed');
});

[
  ['success', 200, '{"payload":{"success":true}}', undefined, 'success_true'],
  [
    'rejection',
    200,
    '{"payload":{"success":false}}',
    'invite_rejected',
    'success_false',
  ],
  [
    'missing success flag',
    200,
    '{"payload":{}}',
    'invite_unknown',
    'success_missing',
  ],
  ['invalid JSON', 200, '{invalid', 'invite_unknown', 'malformed'],
  ['array payload', 200, '{"payload":[]}', 'invite_unknown', 'malformed'],
  [
    'HTTP 500',
    500,
    '{"payload":{"success":true}}',
    'invite_unknown',
    'non_200',
  ],
].forEach(([name, status, body, error, responseClass]) => {
  test(`classifies an invite ${name} response as ${responseClass}`, async () => {
    const state = operations.operationState();
    const page = fakePage();
    const browserRequest = invitePost();
    state.inviteRequest = browserRequest;
    await operations.attachObservers(page, state, config, undefined);

    page.emit('response', inviteResponse(browserRequest, status, body));
    const outcome = await state.inviteResponseReady;

    assert.equal(outcome.ok, error === undefined);
    assert.equal(outcome.error, error);
    assert.equal(state.inviteResponseClass, responseClass);
  });
});

test('a second invite response is a duplicate even after success', async () => {
  const state = operations.operationState();
  const page = fakePage();
  const browserRequest = invitePost();
  state.inviteRequest = browserRequest;
  await operations.attachObservers(page, state, config, undefined);

  page.emit(
    'response',
    inviteResponse(browserRequest, 200, '{"payload":{"success":true}}')
  );
  await state.inviteResponseReady;
  page.emit(
    'response',
    inviteResponse(browserRequest, 200, '{"payload":{"success":true}}')
  );

  assert.equal(state.inviteOutcome?.error, 'invite_unknown');
  assert.equal(state.inviteResponseClass, 'duplicate');
});

test('an invite body read stops when the response deadline signal aborts', async () => {
  const state = operations.operationState();
  const page = fakePage();
  const browserRequest = invitePost();
  const deadline = new AbortController();
  state.inviteRequest = browserRequest;
  state.inviteResponseSignal = deadline.signal;
  await operations.attachObservers(page, state, config, undefined);

  page.emit('response', {
    request: () => browserRequest,
    status: () => 200,
    text: () => new Promise(() => {}),
  });
  deadline.abort(new Error('invite_response_timeout'));
  const outcome = await state.inviteResponseReady;

  assert.equal(outcome.error, 'invite_unknown');
  assert.equal(state.inviteResponseClass, 'timeout');
  await Promise.allSettled([...state.inviteTasks]);
  assert.equal(state.inviteTasks.size, 0);
});

function rolesDocument(groups, container = {}) {
  return { data: { get_app_roles: { app_roles: groups, ...container } } };
}

function testers(users, group = {}) {
  return { role: 'instagram testers', users, ...group };
}

function rolesFailure(callback) {
  assert.throws(callback, error => error.code === 'unknown_status');
}

test('rolesStatusMap maps pending and confirmed testers', () => {
  const statuses = operations.rolesStatusMap(
    rolesDocument([
      testers([
        { id: TARGET_ID, status: 'PENDING' },
        { id: '178414000000000002', status: 'CONFIRMED' },
      ]),
      { role: 'developers', users: [{ id: '5', status: 'CONFIRMED' }] },
    ])
  );

  assert.deepEqual(
    [...statuses],
    [
      [TARGET_ID, 'pending'],
      ['178414000000000002', 'accepted'],
    ]
  );
});

test('an empty or missing testers group is an empty map and absent', () => {
  [
    rolesDocument([]),
    rolesDocument([{ role: 'developers', users: [] }]),
    rolesDocument([testers([])]),
  ].forEach(document => {
    assert.equal(operations.rolesStatusMap(document).size, 0);
    assert.equal(
      operations.parseRolesStatus(JSON.stringify(document), TARGET_ID),
      'absent'
    );
  });
});

test('rolesStatusMap refuses incomplete, malformed or conflicting rosters', () => {
  [
    rolesDocument([], { page_info: { has_next_page: true } }),
    rolesDocument([testers([], { page_info: { has_next_page: true } })]),
    rolesDocument([
      testers([
        { id: TARGET_ID, status: 'PENDING' },
        { id: TARGET_ID, status: 'CONFIRMED' },
      ]),
    ]),
    rolesDocument([testers([{ id: 'abc', status: 'PENDING' }])]),
    rolesDocument([testers([{ id: TARGET_ID, status: 'INVITED' }])]),
    rolesDocument([{ role: 'instagram testers' }]),
    { data: { get_app_roles: [] } },
    { data: {} },
  ].forEach(document => {
    rolesFailure(() => operations.rolesStatusMap(document));
    rolesFailure(() =>
      operations.parseRolesStatus(JSON.stringify(document), TARGET_ID)
    );
  });
});

test('parseRolesStatus keeps its lookup and its selection check', () => {
  const document = JSON.stringify(
    rolesDocument([testers([{ id: TARGET_ID, status: 'CONFIRMED' }])])
  );

  assert.equal(operations.parseRolesStatus(document, TARGET_ID), 'accepted');
  assert.equal(
    operations.parseRolesStatus(document, '178414000000000002'),
    'absent'
  );
  assert.throws(
    () => operations.parseRolesStatus(document, 'abc'),
    error => error.code === 'invalid_selection'
  );
});
