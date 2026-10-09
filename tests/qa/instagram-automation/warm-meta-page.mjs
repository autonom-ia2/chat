/*
 * Local-only warm-page contract test. It uses the existing synthetic HTTPS
 * transport and real Playwright Chromium; no Meta, AWS, credentials, or
 * production profile are involved.
 */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import {
  executeBrowserOperation,
  createWarmMetaPage,
  acceptFreshRolesResponse,
} from '../../../scripts/instagram_testers/browser-operations.mjs';
import {
  handleBrowserRoute,
  isAllowedBrowserRequest,
} from '../../../scripts/instagram_testers/session-manager.mjs';
import { rolesQueryFields } from '../../../scripts/instagram_testers/session-observer.mjs';
import {
  createFixtureTransport,
  loadChromium,
  makeConfiguration,
  makeRequest,
} from './latency-benchmark.mjs';

const FIXTURE_PATH = new URL(
  './latency-browser-fixtures.json',
  import.meta.url
);
const SCENARIOS = ['search', 'status_accepted', 'invite_unknown'];
const INVITE_PATH = '/apps/10001/async/instagram/roles/add/';
const SUCCESS_BODY = '{"payload":{"success":true}}';
const INVITE_SIGNAL_MS = 60000;
const SETTLE_POLL_MS = 100;
const SETTLE_STABLE_MS = 3000;

async function setup(fixture, scenario) {
  const configuration = makeConfiguration(fixture);
  const transport = await createFixtureTransport(fixture, SCENARIOS);
  transport.setScenario(scenario);
  const chromium = await loadChromium();
  const browser = await chromium.launch({
    headless: true,
    ignoreHTTPSErrors: true,
    executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH,
    proxy: { server: transport.proxy },
    args: [
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-default-apps',
      '--disable-sync',
    ],
  });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  await context.route('**/*', route =>
    handleBrowserRoute(route, configuration, process.stderr)
  );
  const page = await context.newPage();
  let gotoCount = 0;
  const realGoto = page.goto.bind(page);
  page.goto = async (...args) => {
    gotoCount += 1;
    return realGoto(...args);
  };
  const responsePromise = page.waitForResponse(response => {
    try {
      const request = response.request();
      const fields = rolesQueryFields(request.postData() || '', configuration);
      return (
        response.url() === 'https://developers.facebook.com/api/graphql/' &&
        request.method() === 'POST' &&
        response.status() === 200 &&
        Reflect.get(fields ?? {}, '__aaid') === fixture.configuration.roles_aaid
      );
    } catch {
      return false;
    }
  });
  await page.goto(configuration.rolesUrl);
  const response = await responsePromise;
  const body = await response.text();
  const warmMetaPage = createWarmMetaPage({
    page,
    configuration,
  });
  acceptFreshRolesResponse(warmMetaPage, {
    page,
    configuration,
    request: response.request(),
    response,
    body,
    source: 'manager_refresh',
  });
  return {
    configuration,
    transport,
    browser,
    context,
    page,
    warmMetaPage,
    getGotoCount: () => gotoCount,
  };
}

async function closeSetup(setupState) {
  setupState.warmMetaPage.dispose();
  await setupState.context.close().catch(() => {});
  await setupState.browser.close().catch(() => {});
  await setupState.transport.close();
}

function permitReply(observation, fields) {
  return {
    type: 'browser_operation',
    operation: 'invite_permit',
    id: observation.id,
    request_id: observation.request_id,
    claim: observation.claim,
    ...fields,
  };
}

const denyInvite = observation =>
  permitReply(observation, { error_code: 'invalid_selection' });

async function operation({
  page,
  configuration,
  warmMetaPage,
  request,
  signal,
  searchStatus,
  warmInvite,
  permitInvite = denyInvite,
}) {
  return executeBrowserOperation({
    page,
    configuration,
    request,
    warmMetaPage,
    searchStatus,
    warmInvite,
    signal: signal || AbortSignal.timeout(10000),
    requestGuard: parameters =>
      isAllowedBrowserRequest({ ...parameters, config: configuration }),
    permitInvite: request.action === 'invite' ? permitInvite : undefined,
  });
}

// The fixture counts an invite after reading its body, so wait until the
// count has been stable for 3 s before checking write invariants.
async function settledInviteCount(transport) {
  let last = transport.counts().invite;
  let stableSince = Date.now();
  while (Date.now() - stableSince < SETTLE_STABLE_MS) {
    // eslint-disable-next-line no-await-in-loop -- polling is serial by design.
    await delay(SETTLE_POLL_MS);
    const current = transport.counts().invite;
    if (current !== last) {
      last = current;
      stableSince = Date.now();
    }
  }
  return last;
}

// A write permit plus Meta's success body: the invite is expected to post once.
async function successfulWarmInvite(state, fixture, iteration) {
  state.transport.setScenario('invite_unknown');
  state.transport.setResponseFault({ path: INVITE_PATH, body: SUCCESS_BODY });
  const before = state.transport.counts().invite;
  try {
    const result = await operation({
      ...state,
      warmInvite: true,
      signal: AbortSignal.timeout(INVITE_SIGNAL_MS),
      permitInvite: observation =>
        permitReply(observation, { decision: 'write', status: 'absent' }),
      request: makeRequest(
        'invite_unknown',
        state.configuration,
        fixture,
        iteration
      ),
    });
    return {
      result,
      delta: (await settledInviteCount(state.transport)) - before,
    };
  } finally {
    state.transport.setResponseFault(null);
  }
}

async function runAbortCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    const controller = new AbortController();
    state.transport.setResponseFault({
      path: '/api/graphql/',
      delayMs: 1000,
    });
    const timer = setTimeout(
      () => controller.abort(new Error('test_operation_timeout')),
      25
    );
    const result = await operation({
      ...state,
      signal: controller.signal,
      request: makeRequest('status_accepted', state.configuration, fixture, 1),
    });
    clearTimeout(timer);
    assert.equal(result.error_code, 'meta_unavailable');
    assert.equal(state.warmMetaPage.valid, false);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runPageCloseCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    await state.page.close();
    assert.equal(state.warmMetaPage.valid, false);
    const result = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 1),
    });
    assert.equal(result.error_code, 'meta_unavailable');
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runLoginNavigationCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    await state.page.goto(
      new URL('/login/', state.configuration.rolesUrl).href,
      { waitUntil: 'commit' }
    );
    assert.equal(state.warmMetaPage.valid, false);
    assert.equal(state.warmMetaPage.invalidReason, 'page_changed');
    state.transport.setResponseFault({
      path: '/api/graphql/',
      status: 403,
      body: '{"error":"login_required"}',
    });
    const result = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 5),
    });
    assert.equal(result.error_code, 'meta_session_expired');
    assert.equal(state.warmMetaPage.valid, false);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runTerminalInvalidationNavigationCase(fixture, kind) {
  const state = await setup(fixture, 'status_accepted');
  try {
    if (kind === 'csrf') {
      state.transport.setResponseFault({
        path: '/api/graphql/',
        status: 403,
        body: '{"error":"expired"}',
      });
    } else {
      state.transport.setResponseFault({
        path: '/api/graphql/',
        disconnect: true,
        persistent: true,
      });
    }
    const failed = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 15),
    });
    const expectedCode =
      kind === 'csrf' ? 'meta_session_expired' : 'meta_unavailable';
    const expectedReason = kind === 'csrf' ? 'csrf_expired' : 'proxy_error';
    assert.equal(failed.error_code, expectedCode);
    assert.equal(state.warmMetaPage.invalidReason, expectedReason);
    await state.page.goto(
      new URL('/login/', state.configuration.rolesUrl).href,
      { waitUntil: 'commit' }
    );
    assert.equal(state.warmMetaPage.invalidReason, expectedReason);
    const rolesBeforeRejectedSearch = state.transport.counts().roles;
    const rejectedSearch = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 16),
    });
    assert.equal(rejectedSearch.error_code, expectedCode);
    assert.equal(state.transport.counts().roles, rolesBeforeRejectedSearch);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runConfigurationMismatchCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    const alternateConfiguration = {
      ...state.configuration,
      appId: '10009',
      rolesUrl:
        'https://developers.facebook.com/apps/10009/roles/roles/?business_id=10002',
    };
    const rolesBefore = state.transport.counts().roles;
    const result = await operation({
      ...state,
      configuration: alternateConfiguration,
      request: makeRequest(
        'status_accepted',
        alternateConfiguration,
        fixture,
        6
      ),
    });
    assert.equal(result.error_code, 'meta_session_expired');
    assert.equal(state.transport.counts().roles, rolesBefore);
    assert.equal(state.warmMetaPage.valid, true);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runAaidMismatchCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    state.warmMetaPage.rolesAaid = '9000002';
    const result = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 7),
    });
    assert.equal(result.error_code, 'unknown_status');
    assert.equal(state.warmMetaPage.valid, false);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runWarmFaultCase(fixture, fault, expectedCode) {
  const state = await setup(fixture, 'status_accepted');
  try {
    state.transport.setResponseFault({
      path: '/api/graphql/',
      ...fault,
    });
    const result = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 8),
    });
    assert.equal(result.error_code, expectedCode);
    assert.equal(state.warmMetaPage.valid, false);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runDuplicateRolesCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  let duplicateScheduled = false;
  try {
    state.transport.setResponseFault({
      path: '/api/graphql/',
      delayMs: 250,
      onHit: () => {
        if (duplicateScheduled) return;
        duplicateScheduled = true;
        setTimeout(() => {
          state.page
            .evaluate(() => {
              const body = new URLSearchParams([
                ['fb_api_req_friendly_name', 'RolesTable_Query'],
                ['doc_id', '10003'],
                ['__bid', '10002'],
                ['__user', '12345'],
                ['av', '12345'],
                ['variables', '{"app_id":"10001"}'],
                ['__aaid', '9000001'],
              ]);
              return fetch('https://developers.facebook.com/api/graphql/', {
                method: 'POST',
                credentials: 'include',
                body,
              });
            })
            .catch(() => {});
        }, 0);
      },
    });
    const result = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 9),
    });
    assert.equal(result.error_code, 'unknown_status');
    assert.equal(state.transport.counts().roles >= 3, true);
    assert.equal(state.warmMetaPage.valid, false);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runDialogGuardCase(fixture) {
  const state = await setup(fixture, 'search');
  try {
    const first = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 10),
    });
    assert.equal(first.results?.length, 1);
    await state.page.evaluate(() => {
      document.querySelectorAll('#tester-dialog button').forEach(button => {
        if (/^(?:Cancel|Close)$/i.test(button.textContent.trim()))
          button.remove();
      });
    });
    const missingClose = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 11),
    });
    assert.equal(missingClose.error_code, 'meta_unavailable');
    assert.equal(state.transport.counts().invite, 0);
    await state.page.evaluate(() => {
      const dialog = document.getElementById('tester-dialog');
      ['Cancel', 'Cancel'].forEach(label => {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        dialog.append(button);
      });
    });
    const ambiguousClose = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 12),
    });
    assert.equal(ambiguousClose.error_code, 'meta_unavailable');
    assert.equal(state.transport.counts().invite, 0);
    await state.page.evaluate(() => {
      const dialog = document.getElementById('tester-dialog');
      dialog.querySelectorAll('button').forEach(button => {
        if (/^(?:Cancel|Close)$/i.test(button.textContent.trim()))
          button.remove();
      });
      const cancel = document.createElement('button');
      cancel.type = 'button';
      cancel.textContent = 'Cancel';
      cancel.disabled = true;
      dialog.append(cancel);
      const close = document.createElement('button');
      close.type = 'button';
      close.textContent = 'Close';
      close.addEventListener('click', () => {
        dialog.hidden = true;
      });
      dialog.append(close);
    });
    const disabledCancel = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 13),
    });
    assert.equal(disabledCancel.error_code, 'meta_unavailable');
    assert.equal(state.transport.counts().invite, 0);
    await state.page.evaluate(() => {
      const dialog = document.getElementById('tester-dialog');
      dialog.querySelectorAll('button').forEach(button => {
        if (/^(?:Cancel|Close)$/i.test(button.textContent.trim()))
          button.remove();
      });
      const close = document.createElement('button');
      close.type = 'button';
      close.textContent = 'Close';
      close.addEventListener('click', () => {
        dialog.hidden = true;
      });
      dialog.append(close);
    });
    const closeFallback = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 14),
    });
    assert.equal(closeFallback.results?.length, 1);
    assert.equal(state.transport.counts().invite, 0);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function runConcurrentCase(fixture) {
  const state = await setup(fixture, 'status_accepted');
  try {
    state.transport.setResponseFault({
      path: '/api/graphql/',
      delayMs: 250,
    });
    const [first, second] = await Promise.all([
      operation({
        ...state,
        request: makeRequest(
          'status_accepted',
          state.configuration,
          fixture,
          13
        ),
      }),
      operation({
        ...state,
        request: makeRequest(
          'status_accepted',
          state.configuration,
          fixture,
          14
        ),
      }),
    ]);
    const outcomes = [first, second];
    assert.equal(
      outcomes.filter(result => result.status === 'accepted').length,
      1
    );
    assert.equal(
      outcomes.filter(result => result.error_code === 'busy').length,
      1
    );
    assert.equal(state.transport.counts().roles, 2);
    assert.equal(state.warmMetaPage.valid, true);
    return true;
  } finally {
    await closeSetup(state);
  }
}

const LEGACY_CANDIDATE_KEYS = ['avatar_url', 'id', 'name', 'username'];

// Search reports the tester status of the exact username only, and only with
// the flag on. The fixture definition is restored for the later cases.
async function runSearchStatusCase(fixture) {
  const definition = fixture.scenarios.search;
  const original = { ...definition };
  const state = await setup(fixture, 'search');
  let iteration = 20;
  const search = async searchStatus => {
    iteration += 1;
    const result = await operation({
      ...state,
      searchStatus,
      request: makeRequest('search', state.configuration, fixture, iteration),
    });
    assert.equal(Array.isArray(result.results), true);
    return result.results;
  };
  try {
    const [legacy] = await search(false);
    assert.deepEqual(Object.keys(legacy).sort(), LEGACY_CANDIDATE_KEYS);

    const exactStatus = async (rolesStatus, expected) => {
      definition.roles_target_status = rolesStatus;
      const [exact] = await search(true);
      assert.deepEqual(
        Object.keys(exact).sort(),
        [...LEGACY_CANDIDATE_KEYS, 'tester_status'].sort()
      );
      assert.equal(exact.username, fixture.target.username);
      assert.equal(exact.tester_status, expected);
      return exact.tester_status;
    };
    const statuses = [
      await exactStatus('ABSENT', 'absent'),
      await exactStatus('CONFIRMED', 'accepted'),
      await exactStatus('PENDING', 'pending'),
    ];

    definition.roles_target_status = 'CONFIRMED';
    definition.typeahead_entries = 'target_and_other';
    const pair = await search(true);
    assert.equal(pair.length, 2);
    const exact = pair.find(item => item.username === fixture.target.username);
    const other = pair.find(item => item.username !== fixture.target.username);
    assert.equal(exact.tester_status, 'accepted');
    assert.equal(other.tester_status, null);

    assert.equal(state.getGotoCount(), 1);
    assert.equal(state.transport.counts().invite, 0);
    return statuses;
  } finally {
    Object.assign(definition, original);
    await closeSetup(state);
  }
}

// With the flag on, the same sequence as the cold-invite run reuses the warm
// page: the invite refreshes roles in place instead of navigating.
async function runWarmInviteReuseCase(fixture) {
  const definition = fixture.scenarios.status_accepted;
  const original = { ...definition };
  const state = await setup(fixture, 'status_accepted');
  try {
    definition.roles_target_status = 'ABSENT';
    const absent = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('status_accepted', state.configuration, fixture, 30),
    });
    assert.equal(absent.status, 'absent');
    state.transport.setScenario('search');
    const firstSearch = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('search', state.configuration, fixture, 31),
    });
    assert.equal(firstSearch.results?.length, 1);
    const secondSearch = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('search', state.configuration, fixture, 32),
    });
    assert.equal(secondSearch.results?.length, 1);
    assert.equal(state.getGotoCount(), 1);

    state.transport.setScenario('invite_unknown');
    const rolesBeforeInvite = state.transport.counts().roles;
    const invite = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('invite_unknown', state.configuration, fixture, 33),
    });
    assert.equal(invite.error_code, 'invalid_selection');
    assert.equal(invite.write_started, false);
    assert.equal(await settledInviteCount(state.transport), 0);
    assert.equal(state.getGotoCount(), 1);
    assert.equal(state.transport.counts().roles, rolesBeforeInvite + 1);
    assert.equal(state.warmMetaPage.valid, true);

    definition.roles_target_status = 'CONFIRMED';
    state.transport.setScenario('status_accepted');
    const statusAfterInvite = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('status_accepted', state.configuration, fixture, 34),
    });
    assert.equal(statusAfterInvite.status, 'accepted');
    assert.equal(state.getGotoCount(), 1);
    return true;
  } finally {
    Object.assign(definition, original);
    await closeSetup(state);
  }
}

// A warm search leaves the dialog open; the warm invite resets it and writes
// exactly once without navigating.
async function runInviteAfterSearchCase(fixture) {
  const state = await setup(fixture, 'search');
  try {
    const search = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('search', state.configuration, fixture, 40),
    });
    assert.equal(search.results?.length, 1);
    assert.equal(await state.page.locator('#tester-dialog').isVisible(), true);
    const { result, delta } = await successfulWarmInvite(state, fixture, 41);
    assert.equal(result.error_code, undefined);
    assert.equal(result.invited, true);
    assert.equal(result.status, 'pending');
    assert.equal(result.write_started, true);
    assert.equal(delta, 1);
    assert.equal(state.getGotoCount(), 1);
    return true;
  } finally {
    await closeSetup(state);
  }
}

// The fixture's Cancel keeps a selected token. A warm invite that finds one
// fails closed before any permit and marks the page changed, so the next
// operation recovers with a cold navigation instead of failing until refresh.
async function runResidueRecoveryCase(fixture) {
  const state = await setup(fixture, 'search');
  try {
    const search = await operation({
      ...state,
      warmInvite: true,
      request: makeRequest('search', state.configuration, fixture, 50),
    });
    assert.equal(search.results?.length, 1);
    await state.page
      .locator('#latency-listbox [role="option"]')
      .click({ timeout: 5000 });

    state.transport.setScenario('invite_unknown');
    const before = state.transport.counts().invite;
    let permitCalls = 0;
    const residue = await operation({
      ...state,
      warmInvite: true,
      signal: AbortSignal.timeout(INVITE_SIGNAL_MS),
      permitInvite: observation => {
        permitCalls += 1;
        return permitReply(observation, {
          decision: 'write',
          status: 'absent',
        });
      },
      request: makeRequest('invite_unknown', state.configuration, fixture, 51),
    });
    assert.equal(residue.error_code, 'invalid_selection');
    assert.equal(residue.write_started, false);
    assert.equal(permitCalls, 0);
    assert.equal((await settledInviteCount(state.transport)) - before, 0);
    assert.equal(state.warmMetaPage.valid, false);
    assert.equal(state.warmMetaPage.invalidReason, 'page_changed');
    assert.equal(state.getGotoCount(), 1);

    const { result, delta } = await successfulWarmInvite(state, fixture, 52);
    assert.equal(result.invited, true);
    assert.equal(result.write_started, true);
    assert.equal(delta, 1);
    assert.equal(state.getGotoCount(), 2);
    assert.equal(state.warmMetaPage.valid, true);
    return true;
  } finally {
    await closeSetup(state);
  }
}

async function run() {
  const fixture = JSON.parse(await readFile(FIXTURE_PATH, 'utf8'));
  assert.equal(fixture.production_mutated, false);
  assert.equal(fixture.meta_called, false);
  const state = await setup(fixture, 'status_accepted');
  try {
    const accepted = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 1),
    });
    fixture.scenarios.status_accepted.roles_target_status = 'ABSENT';
    const absent = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 2),
    });
    assert.equal(accepted.status, 'accepted');
    assert.equal(absent.status, 'absent');
    assert.equal(state.getGotoCount(), 1);

    state.transport.setScenario('search');
    const firstSearch = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 1),
    });
    assert.equal(firstSearch.results?.length, 1);
    const secondSearch = await operation({
      ...state,
      request: makeRequest('search', state.configuration, fixture, 2),
    });
    assert.equal(secondSearch.results?.length, 1);
    assert.equal(state.getGotoCount(), 1);

    state.transport.setScenario('invite_unknown');
    const rolesBeforeInvite = state.transport.counts().roles;
    const invite = await operation({
      ...state,
      request: makeRequest('invite_unknown', state.configuration, fixture, 1),
    });
    assert.equal(invite.error_code, 'invalid_selection');
    assert.equal(invite.write_started, false);
    assert.equal(state.transport.counts().invite, 0);
    assert.equal(state.getGotoCount(), 2);
    assert.equal(state.transport.counts().roles, rolesBeforeInvite + 1);
    assert.equal(state.warmMetaPage.valid, true);

    fixture.scenarios.status_accepted.roles_target_status = 'CONFIRMED';
    state.transport.setScenario('status_accepted');
    const statusAfterInvite = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 3),
    });
    assert.equal(statusAfterInvite.status, 'accepted');
    assert.equal(state.getGotoCount(), 2);

    state.transport.setResponseFault({
      path: '/api/graphql/',
      status: 403,
      body: '{"error":"expired"}',
    });
    const expired = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 3),
    });
    assert.equal(expired.error_code, 'meta_session_expired');
    assert.equal(state.warmMetaPage.valid, false);
    const rolesBeforeRejectedReuse = state.transport.counts().roles;
    const rejectedReuse = await operation({
      ...state,
      request: makeRequest('status_accepted', state.configuration, fixture, 4),
    });
    assert.equal(rejectedReuse.error_code, 'meta_session_expired');
    assert.equal(state.transport.counts().roles, rolesBeforeRejectedReuse);

    state.transport.setResponseFault(null);
    state.transport.setScenario('invite_unknown');
    const inviteAfterExpiry = await operation({
      ...state,
      request: makeRequest('invite_unknown', state.configuration, fixture, 2),
    });
    assert.equal(inviteAfterExpiry.error_code, 'meta_session_expired');
    assert.equal(inviteAfterExpiry.write_started, false);
    assert.equal(state.transport.counts().invite, 0);
    assert.equal(state.getGotoCount(), 2);

    return {
      status: 'passed',
      production_mutated: false,
      meta_called: false,
      warm_status_sequence: ['accepted', 'absent', 'accepted'],
      repeated_searches: 2,
      goto_count: state.getGotoCount(),
      roles_requests: state.transport.counts().roles,
      invite_requests: state.transport.counts().invite,
      expired_rejected: true,
      invite_cold_reseeded: true,
      status_after_invite_reused_warm: true,
      initial_roles_post_pinned: true,
      cancel_close_controls_in_fixture: true,
      abort_invalidated: await runAbortCase(fixture),
      page_close_invalidated: await runPageCloseCase(fixture),
      login_navigation_failclosed: await runLoginNavigationCase(fixture),
      csrf_terminal_reason_preserved:
        await runTerminalInvalidationNavigationCase(fixture, 'csrf'),
      proxy_terminal_reason_preserved:
        await runTerminalInvalidationNavigationCase(fixture, 'proxy'),
      configuration_mismatch_rejected:
        await runConfigurationMismatchCase(fixture),
      aaid_mismatch_rejected: await runAaidMismatchCase(fixture),
      response_500_rejected: await runWarmFaultCase(
        fixture,
        { status: 500, body: '{"error":"synthetic_server_failure"}' },
        'meta_unavailable'
      ),
      incomplete_response_rejected: await runWarmFaultCase(
        fixture,
        { body: '{"data":' },
        'unknown_status'
      ),
      duplicate_roles_rejected: await runDuplicateRolesCase(fixture),
      dialog_guards_fail_closed: await runDialogGuardCase(fixture),
      concurrent_refresh_serialized: await runConcurrentCase(fixture),
      search_status_exact_only: await runSearchStatusCase(fixture),
      invite_reused_warm: await runWarmInviteReuseCase(fixture),
      invite_after_search_resets_dialog_and_writes_once:
        await runInviteAfterSearchCase(fixture),
      residue_invalidates_then_recovers_cold:
        await runResidueRecoveryCase(fixture),
    };
  } finally {
    await closeSetup(state);
  }
}

run()
  .then(report => process.stdout.write(`${JSON.stringify(report)}\n`))
  .catch(error => {
    process.stdout.write(
      `${JSON.stringify({
        status: 'failed',
        error_class: error?.name || 'Error',
        error_code: error?.code || null,
        production_mutated: false,
        meta_called: false,
      })}\n`
    );
    process.exitCode = 1;
  });
