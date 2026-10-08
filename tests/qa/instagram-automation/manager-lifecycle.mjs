/*
 * Local-only lifecycle harness for the real Instagram manager.
 *
 * The browser talks only to the synthetic HTTPS/proxy fixture exported by the
 * latency benchmark. The publisher is an in-memory protocol peer, the profile
 * is a fresh private directory, and the cookie values are synthetic. This
 * file must never be pointed at a production profile or publisher.
 */
/* eslint-disable no-await-in-loop, no-use-before-define, no-restricted-syntax -- Lifecycle steps and protocol events are intentionally ordered. */

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { lstat, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  createFixtureHtml,
  createFixtureTransport,
  loadChromium,
  makeConfiguration,
  makeRequest,
} from './latency-benchmark.mjs';
import { executeBrowserOperation } from '../../../scripts/instagram_testers/browser-operations.mjs';
import { run } from '../../../scripts/instagram_testers/session-manager.mjs';
import { isMainModule } from '../../../scripts/instagram_testers/runtime/entrypoint.mjs';

const FIXTURE_PATH = new URL(
  './latency-browser-fixtures.json',
  import.meta.url
);
const ORIGIN = 'https://developers.facebook.com';
const ROLES_PATH = '/apps/10001/roles/roles/';
const GRAPHQL_PATH = '/api/graphql/';
const REPORT_VERSION = 1;
const WATCHDOG_MS = 20000;
const COOKIE_VALUES = Object.freeze({
  c_user: '12345',
  xs: 'synthetic_cookie',
});

function fail(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

function safeClass(error) {
  const value = error?.name || error?.constructor?.name || 'Error';
  return /^[A-Za-z][A-Za-z0-9_:]{0,95}$/.test(value) ? value : 'Error';
}

function safeCode(error) {
  const value = error?.code || error?.message;
  return typeof value === 'string' && /^[a-z][a-z0-9_]{0,95}$/.test(value)
    ? value
    : null;
}

function safeAssertionValue(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && /^[a-z_]{1,96}$/.test(value)) return value;
  return null;
}

function sourceLine(error) {
  const stack = typeof error?.stack === 'string' ? error.stack : '';
  const match = stack.match(/manager-lifecycle\.mjs:(\d+):(\d+)/);
  return match ? Number(match[1]) : null;
}

function countEvents(state, operation) {
  return state.events.filter(event => event.operation === operation).length;
}

async function exists(path) {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

function augmentedRolesHtml(fixture) {
  // observedSession requires these three request fields. They are synthetic
  // fixture values and never leave the local browser/proxy process.
  return createFixtureHtml(fixture, 'status_accepted').replace(
    "['__aaid', '9000001'],",
    "['__aaid', '9000001'], ['fb_dtsg', 'synthetic_fb_dtsg'], ['jazoest', 'synthetic_jazoest'], ['lsd', 'synthetic_lsd'],"
  );
}

function operationRequest(configuration, fixture) {
  const request = makeRequest('status_accepted', configuration, fixture, 1);
  return {
    ...request,
    state: 'queued',
    deadline: new Date(Date.now() + 60000).toISOString(),
  };
}

function syntheticBootstrap(env) {
  return {
    type: 'bootstrap',
    metadata: {
      INSTAGRAM_META_DEVELOPER_APP_ID: env.INSTAGRAM_META_DEVELOPER_APP_ID,
      INSTAGRAM_META_BUSINESS_ID: env.INSTAGRAM_META_BUSINESS_ID,
      INSTAGRAM_TESTER_APP_NAME: 'Synthetic Browser Lifecycle',
      INSTAGRAM_TESTER_ADMIN_USER_ID: env.INSTAGRAM_TESTER_ADMIN_USER_ID,
      INSTAGRAM_TESTER_ROLES_DOC_ID: env.INSTAGRAM_TESTER_ROLES_DOC_ID,
    },
    revision: 'a'.repeat(64),
    version: null,
  };
}

function makePublisher({
  env,
  configuration,
  request,
  signals,
  stopAfterComplete,
  onSessionPublished,
}) {
  const state = {
    events: [],
    reads: 0,
    claims: 0,
    completes: 0,
    sessionPublications: 0,
    requestAvailable: true,
    watchdogFired: false,
  };

  const record = payload => {
    state.events.push({
      type: typeof payload?.type === 'string' ? payload.type : null,
      operation:
        typeof payload?.operation === 'string' ? payload.operation : null,
      error_code:
        typeof payload?.error_code === 'string' ? payload.error_code : null,
      status: typeof payload?.status === 'string' ? payload.status : null,
    });
  };

  const publish = async (command, payload, { signal } = {}) => {
    signal?.throwIfAborted();
    if (!Array.isArray(command) || command.length !== 1)
      fail('synthetic_publisher_command');
    record(payload);
    if (payload?.type === 'session' && payload.operation === 'bootstrap')
      return syntheticBootstrap(env);
    if (payload?.type === 'session' && payload.operation === 'publish') {
      state.sessionPublications += 1;
      onSessionPublished?.();
      return '00000000-0000-4000-8000-000000000001';
    }
    if (payload?.type === 'operator')
      return {
        type: 'operator',
        manager: null,
        request: null,
      };
    if (payload?.type !== 'browser_operation')
      fail('synthetic_publisher_payload');
    if (payload.operation === 'read') {
      state.reads += 1;
      const next = state.requestAvailable ? request : null;
      state.requestAvailable = false;
      return { type: 'browser_operation', operation: 'read', request: next };
    }
    if (payload.operation === 'claim') {
      state.claims += 1;
      return {
        type: 'browser_operation',
        operation: 'claim',
        request: {
          ...request,
          state: 'running',
          claim: request.claim,
        },
      };
    }
    if (payload.operation === 'complete') {
      state.completes += 1;
      if (stopAfterComplete) setTimeout(() => signals.emit('SIGTERM'), 0);
      return {
        type: 'browser_operation',
        operation: 'complete',
        id: payload.id,
        request_id: payload.request_id,
      };
    }
    fail('synthetic_publisher_operation');
  };

  return { publish, state, configuration };
}

function makeDeadlineTestClock() {
  let deadlineScheduled = false;
  let deadlineTimer;
  let faultHit = false;
  let deadlineFired = false;
  return {
    get armed() {
      return deadlineScheduled;
    },
    get deadlineFired() {
      return deadlineFired;
    },
    get faultHit() {
      return faultHit;
    },
    setTimeout(callback, milliseconds) {
      const timer = {
        active: true,
        long: milliseconds >= 100000,
        native: null,
        callback,
      };
      if (timer.long) {
        deadlineScheduled = true;
        deadlineTimer = timer;
      }
      timer.native = globalThis.setTimeout(() => {
        if (!timer.active) return;
        timer.active = false;
        if (timer.long) deadlineFired = true;
        timer.callback();
      }, milliseconds);
      return timer;
    },
    shortenAfterFault() {
      if (!deadlineTimer?.active) return;
      faultHit = true;
      globalThis.clearTimeout(deadlineTimer.native);
      deadlineTimer.native = globalThis.setTimeout(() => {
        if (!deadlineTimer.active) return;
        deadlineTimer.active = false;
        deadlineFired = true;
        const callback = deadlineTimer.callback;
        deadlineTimer.native = null;
        deadlineTimer = undefined;
        callback();
      }, 200);
    },
    clearTimeout(timer) {
      if (!timer?.active) return;
      timer.active = false;
      if (timer.native) globalThis.clearTimeout(timer.native);
    },
  };
}

async function makeRuntime({
  chromium,
  transport,
  state,
  seedCookies,
  cookieContract,
}) {
  const executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
  if (!executablePath || executablePath.includes('\0'))
    fail('playwright_executable_missing');
  return {
    chromium: {
      launchPersistentContext: async (profile, options) => {
        // The manager still validates the VPS sandbox flag. The isolated
        // localhost fixture uses the runner's browser sandbox override only.
        const launchOptions = { ...options };
        delete launchOptions.channel;
        const context = await chromium.launchPersistentContext(profile, {
          ...launchOptions,
          executablePath,
          headless: true,
          chromiumSandbox: false,
          ignoreHTTPSErrors: true,
          proxy: { server: transport.proxy },
        });
        state.contexts += 1;
        context.on('close', () => {
          state.contextClosed += 1;
        });
        if (seedCookies) {
          const expires = Math.floor(Date.now() / 1000) + 3600;
          await context.addCookies([
            {
              name: 'c_user',
              value: COOKIE_VALUES.c_user,
              domain: 'developers.facebook.com',
              path: '/',
              expires,
            },
            {
              name: 'xs',
              value: COOKIE_VALUES.xs,
              domain: 'developers.facebook.com',
              path: '/',
              expires,
            },
          ]);
          state.cookieSets += 1;
          cookieContract.values = { ...COOKIE_VALUES };
        } else {
          const cookies = await context.cookies();
          const actual = new Map(
            cookies.map(cookie => [cookie.name, cookie.value])
          );
          state.cookieRestoreChecked = true;
          state.cookieRestored =
            cookieContract.values !== null &&
            Object.entries(cookieContract.values).every(
              ([name, value]) => actual.get(name) === value
            );
        }
        return context;
      },
    },
  };
}

async function runManagerCase({
  env,
  configuration,
  fixture,
  transport,
  chromium,
  profile,
  closePageDuringOperation,
  stopAfterComplete,
  clock = globalThis,
  onSessionPublished,
  seedCookies = false,
  cookieContract,
}) {
  const signals = new EventEmitter();
  const state = {
    contexts: 0,
    contextClosed: 0,
    cookieSets: 0,
    cookieRestoreChecked: false,
    cookieRestored: false,
    pageClosedAfterOperation: false,
    closeTriggered: false,
    events: [],
  };
  const request = operationRequest(configuration, fixture);
  const publisher = makePublisher({
    env,
    configuration,
    request,
    signals,
    stopAfterComplete,
    onSessionPublished,
  });
  state.publisher = publisher.state;

  const loadRuntime = async () =>
    makeRuntime({
      chromium,
      transport,
      state,
      seedCookies,
      cookieContract,
    });
  let closeArmed = closePageDuringOperation;
  const executeOperation = async parameters => {
    let closeListener;
    if (closeArmed) {
      closeArmed = false;
      closeListener = response => {
        if (
          response.url() === `${ORIGIN}${GRAPHQL_PATH}` &&
          response.request().method() === 'POST'
        ) {
          state.closeTriggered = true;
          queueMicrotask(() => {
            parameters.page.close().catch(() => {});
          });
        }
      };
      parameters.page.on('response', closeListener);
    }
    try {
      const result = await executeBrowserOperation(parameters);
      state.pageClosedAfterOperation = parameters.page.isClosed();
      return result;
    } finally {
      if (closeListener) parameters.page.off('response', closeListener);
    }
  };

  const stdout = { write: () => true };
  const stderr = { write: () => true };
  const watchdog = setTimeout(() => {
    publisher.state.watchdogFired = true;
    signals.emit('SIGTERM');
  }, WATCHDOG_MS);
  let result;
  try {
    result = await run(env, {
      signals,
      publish: publisher.publish,
      loadRuntime,
      executeOperation,
      clock,
      stdout,
      stderr,
    });
  } catch (error) {
    result = { error };
  } finally {
    clearTimeout(watchdog);
  }
  state.events = publisher.state.events;
  console.log(
    JSON.stringify({
      event: 'fixture_manager_cycle',
      result_error: safeCode(result?.error),
      contexts: state.contexts,
      context_closed: state.contextClosed,
      close_triggered: state.closeTriggered,
      watchdog_fired: state.publisher.watchdogFired,
      reads: state.publisher.reads,
      claims: state.publisher.claims,
      completes: state.publisher.completes,
      events: state.events.map(event => ({
        type: event.type,
        operation: event.operation,
        state: event.state || null,
        status: event.status || null,
        error_code: event.error_code || null,
      })),
    })
  );
  return { result, state };
}

function assertError(result, code) {
  assert.ok(result && result.error, 'manager should return an error');
  assert.equal(result.error.message, code);
}

async function runLifecycle() {
  const fixture = JSON.parse(await readFile(FIXTURE_PATH, 'utf8'));
  assert.equal(fixture.production_mutated, false);
  assert.equal(fixture.meta_called, false);
  const chromium = await loadChromium();
  const transport = await createFixtureTransport(fixture, ['status_accepted']);
  const configuration = makeConfiguration(fixture);
  const profile = await mkdtemp(join(tmpdir(), 'instagram-manager-lifecycle-'));
  const cookieContract = { values: null };
  const env = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    TMPDIR: process.env.TMPDIR || tmpdir(),
    LANG: process.env.LANG || 'C',
    INSTAGRAM_TESTER_RUNTIME_MODE: 'vps',
    INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED: 'true',
    INSTAGRAM_TESTER_CHROMIUM_SANDBOX: 'true',
    INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
    INSTAGRAM_TESTER_PROXY_PORT: new URL(transport.proxy).port,
    INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
    INSTAGRAM_TESTER_PROXY_IDENTITY: '93.184.216.34:8080',
    INSTAGRAM_TESTER_BROWSER_PROFILE: profile,
    INSTAGRAM_TESTER_PLAYWRIGHT_MODULE: process.env.PLAYWRIGHT_MODULE_PATH,
    INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: '["synthetic"]',
    INSTAGRAM_META_DEVELOPER_APP_ID: fixture.configuration.app_id,
    INSTAGRAM_META_BUSINESS_ID: fixture.configuration.business_id,
    INSTAGRAM_TESTER_ROLES_DOC_ID: fixture.configuration.roles_doc_id,
    INSTAGRAM_TESTER_ADMIN_USER_ID: fixture.configuration.admin_id,
  };
  const roleHtml = augmentedRolesHtml(fixture);
  try {
    transport.setScenario('status_accepted');
    transport.setResponseFault({
      path: ROLES_PATH,
      status: 200,
      body: roleHtml,
      contentType: 'text/html; charset=utf-8',
    });
    const closed = await runManagerCase({
      env,
      configuration,
      fixture,
      transport,
      chromium,
      profile,
      closePageDuringOperation: true,
      stopAfterComplete: false,
      seedCookies: true,
      cookieContract,
    });
    assertError(closed.result, 'browser_runtime_required');
    assert.equal(closed.state.closeTriggered, true);
    assert.equal(closed.state.pageClosedAfterOperation, true);
    assert.equal(closed.state.contexts, 1);
    assert.equal(closed.state.contextClosed, 1);
    assert.equal(closed.state.cookieSets, 1);
    assert.equal(closed.state.cookieRestoreChecked, false);
    assert.equal(closed.state.publisher.sessionPublications, 1);
    assert.equal(
      closed.state.events.find(event => event.operation === 'complete')
        ?.error_code,
      'meta_unavailable'
    );
    assert.equal(countEvents(closed.state, 'read'), 1);
    assert.equal(countEvents(closed.state, 'claim'), 1);
    assert.equal(countEvents(closed.state, 'complete'), 1);
    assert.equal(closed.state.publisher.watchdogFired, false);
    assert.equal(await exists(join(profile, '.instagram-manager.lock')), false);
    assert.equal(await exists(profile), true);

    transport.setScenario('status_accepted');
    transport.setResponseFault({
      path: ROLES_PATH,
      status: 200,
      body: roleHtml,
      contentType: 'text/html; charset=utf-8',
    });
    const resumed = await runManagerCase({
      env,
      configuration,
      fixture,
      transport,
      chromium,
      profile,
      closePageDuringOperation: false,
      stopAfterComplete: true,
      cookieContract,
    });
    assert.equal(resumed.result, undefined);
    assert.equal(resumed.state.contexts, 1);
    assert.equal(resumed.state.contextClosed, 1);
    assert.equal(resumed.state.cookieSets, 0);
    assert.equal(resumed.state.cookieRestoreChecked, true);
    assert.equal(resumed.state.cookieRestored, true);
    assert.equal(resumed.state.publisher.sessionPublications, 1);
    assert.equal(
      resumed.state.events.find(event => event.operation === 'complete')
        ?.status,
      'accepted'
    );
    assert.equal(countEvents(resumed.state, 'read'), 1);
    assert.equal(countEvents(resumed.state, 'claim'), 1);
    assert.equal(countEvents(resumed.state, 'complete'), 1);
    assert.equal(resumed.state.publisher.watchdogFired, false);
    assert.equal(await exists(join(profile, '.instagram-manager.lock')), false);
    assert.equal(await exists(profile), true);

    const deadlineClock = makeDeadlineTestClock();
    let timeoutFaultHits = 0;
    transport.setScenario('status_accepted');
    transport.setResponseFault({
      path: ROLES_PATH,
      status: 200,
      body: roleHtml,
      contentType: 'text/html; charset=utf-8',
    });
    const timedOut = await runManagerCase({
      env,
      configuration,
      fixture,
      transport,
      chromium,
      profile,
      closePageDuringOperation: false,
      stopAfterComplete: false,
      clock: deadlineClock,
      cookieContract,
      onSessionPublished: () => {
        if (timeoutFaultHits > 0) return;
        transport.setResponseFault({
          path: GRAPHQL_PATH,
          delayMs: 1000,
          onHit: () => {
            timeoutFaultHits += 1;
            deadlineClock.shortenAfterFault();
          },
        });
      },
    });
    assertError(timedOut.result, 'browser_runtime_required');
    assert.equal(deadlineClock.armed, true);
    assert.equal(timeoutFaultHits, 1);
    assert.equal(deadlineClock.faultHit, true);
    assert.equal(deadlineClock.deadlineFired, true);
    assert.equal(transport.pendingResponseFault(), false);
    assert.equal(timedOut.state.contexts, 1);
    assert.equal(timedOut.state.contextClosed, 1);
    assert.equal(timedOut.state.cookieSets, 0);
    assert.equal(timedOut.state.cookieRestoreChecked, true);
    assert.equal(timedOut.state.cookieRestored, true);
    assert.equal(timedOut.state.publisher.sessionPublications, 1);
    assert.equal(timedOut.state.publisher.watchdogFired, false);
    assert.equal(countEvents(timedOut.state, 'read'), 1);
    assert.equal(countEvents(timedOut.state, 'claim'), 1);
    assert.equal(countEvents(timedOut.state, 'complete'), 0);
    assert.equal(await exists(join(profile, '.instagram-manager.lock')), false);
    assert.equal(await exists(profile), true);

    transport.setScenario('status_accepted');
    transport.setResponseFault({
      path: ROLES_PATH,
      status: 200,
      body: roleHtml,
      contentType: 'text/html; charset=utf-8',
    });
    const resumedAfterTimeout = await runManagerCase({
      env,
      configuration,
      fixture,
      transport,
      chromium,
      profile,
      closePageDuringOperation: false,
      stopAfterComplete: true,
      cookieContract,
    });
    assert.equal(resumedAfterTimeout.result, undefined);
    assert.equal(resumedAfterTimeout.state.contexts, 1);
    assert.equal(resumedAfterTimeout.state.contextClosed, 1);
    assert.equal(resumedAfterTimeout.state.cookieSets, 0);
    assert.equal(resumedAfterTimeout.state.cookieRestoreChecked, true);
    assert.equal(resumedAfterTimeout.state.cookieRestored, true);
    assert.equal(resumedAfterTimeout.state.publisher.sessionPublications, 1);
    assert.equal(
      resumedAfterTimeout.state.events.find(
        event => event.operation === 'complete'
      )?.status,
      'accepted'
    );
    assert.equal(countEvents(resumedAfterTimeout.state, 'read'), 1);
    assert.equal(countEvents(resumedAfterTimeout.state, 'claim'), 1);
    assert.equal(countEvents(resumedAfterTimeout.state, 'complete'), 1);
    assert.equal(resumedAfterTimeout.state.publisher.watchdogFired, false);
    assert.equal(await exists(join(profile, '.instagram-manager.lock')), false);
    assert.equal(await exists(profile), true);

    const counts = transport.counts();
    assert.equal(counts.roles, 8, 'all manager runs must capture Roles');
    assert.equal(counts.typeahead, 0);
    assert.equal(counts.invite, 0);
    return {
      status: 'passed',
      harness: 'manager_browser_lifecycle_local',
      report_version: REPORT_VERSION,
      production_mutated: false,
      meta_called: false,
      closed_page: {
        manager_error: 'browser_runtime_required',
        published_error: 'meta_unavailable',
        read_count: countEvents(closed.state, 'read'),
        claim_count: countEvents(closed.state, 'claim'),
        complete_count: countEvents(closed.state, 'complete'),
        context_closed: closed.state.contextClosed === 1,
        cookie_restore: closed.state.cookieRestored,
        lock_released: !(await exists(
          join(profile, '.instagram-manager.lock')
        )),
      },
      resumed_status: {
        status: 'accepted',
        read_count: countEvents(resumed.state, 'read'),
        claim_count: countEvents(resumed.state, 'claim'),
        complete_count: countEvents(resumed.state, 'complete'),
        context_closed: resumed.state.contextClosed === 1,
        cookie_restore: resumed.state.cookieRestored,
        lock_released: !(await exists(
          join(profile, '.instagram-manager.lock')
        )),
        same_profile_reused: true,
      },
      timed_out_operation: {
        manager_error: 'browser_runtime_required',
        fault_hits: timeoutFaultHits,
        fault_consumed: !transport.pendingResponseFault(),
        deadline_fired: deadlineClock.deadlineFired,
        complete_count: countEvents(timedOut.state, 'complete'),
        context_closed: timedOut.state.contextClosed === 1,
        cookie_restore: timedOut.state.cookieRestored,
        lock_released: !(await exists(
          join(profile, '.instagram-manager.lock')
        )),
        delayed_fixture_response_ms: 1000,
        deadline_timer_scaled_for_local_harness: true,
      },
      resumed_after_timeout: {
        status: 'accepted',
        complete_count: countEvents(resumedAfterTimeout.state, 'complete'),
        context_closed: resumedAfterTimeout.state.contextClosed === 1,
        cookie_restore: resumedAfterTimeout.state.cookieRestored,
        lock_released: !(await exists(
          join(profile, '.instagram-manager.lock')
        )),
        same_profile_reused: true,
      },
      fixture_requests: {
        roles: counts.roles,
        typeahead: counts.typeahead,
        invite: counts.invite,
      },
    };
  } finally {
    await transport.close();
    await rm(profile, { recursive: true, force: true });
  }
}

async function main() {
  try {
    process.stdout.write(`${JSON.stringify(await runLifecycle())}\n`);
  } catch (error) {
    process.stdout.write(
      `${JSON.stringify({
        status: 'error',
        harness: 'manager_browser_lifecycle_local',
        error_class: safeClass(error),
        error_code: safeCode(error),
        source_line: sourceLine(error),
        actual: safeAssertionValue(error?.actual),
        expected: safeAssertionValue(error?.expected),
        production_mutated: false,
        meta_called: false,
      })}\n`
    );
    process.exitCode = 1;
  }
}

if (isMainModule(import.meta.url)) main();

export { runLifecycle };
