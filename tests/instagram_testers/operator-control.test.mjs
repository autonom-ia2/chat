/* eslint-disable no-await-in-loop, no-restricted-syntax -- Sequential synthetic operator lifecycle checks. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import {
  parseEnvelope,
  validateRequest,
} from '../../scripts/instagram_testers/runtime/operator-protocol.mjs';
import {
  runWaiter,
  runtimeChild,
} from '../../scripts/instagram_testers/runtime/operator-waiter.mjs';
import { observerConfiguration } from '../../scripts/instagram_testers/session-manager.mjs';

import { run as recoveryBrowser } from '../../scripts/instagram_testers/session-browser.mjs';

const id = '11111111-1111-4111-8111-111111111111';
const stamp = '2026-10-04T10:00:00.000Z';
const manager = {
  state: 'operator_required',
  control_available: true,
  observed_at: stamp,
};
const request = {
  id,
  action: 'reconnect',
  state: 'queued',
  actor_id: 42,
  created_at: stamp,
  updated_at: stamp,
  expires_at: '2026-10-04T11:00:00.000Z',
};
const envelope = (current = null) => ({
  type: 'operator',
  manager,
  request: current,
});
const metadata = {
  INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
  INSTAGRAM_META_BUSINESS_ID: '10002',
  INSTAGRAM_TESTER_APP_NAME: 'Synthetic App',
  INSTAGRAM_TESTER_ADMIN_USER_ID: '12345',
  INSTAGRAM_TESTER_ROLES_DOC_ID: '10003',
};
const bootstrap = {
  type: 'bootstrap',
  metadata,
  revision: 'a'.repeat(64),
  version: null,
};
const env = {
  INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: '["synthetic"]',
  INSTAGRAM_TESTER_BROWSER_PROFILE: '/synthetic/profile',
  INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
  INSTAGRAM_TESTER_PROXY_PORT: '9100',
  INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
  INSTAGRAM_TESTER_PROXY_IDENTITY: '93.184.216.34:8080',
  INSTAGRAM_META_DEVELOPER_APP_ID: '99999',
  INSTAGRAM_TESTER_ADMIN_USER_ID: '99999',
};

test('only exact typed bounded envelopes, valid dates, actor types and UUIDs are accepted', () => {
  assert.deepEqual(
    parseEnvelope(JSON.stringify(envelope(request))),
    envelope(request)
  );
  assert.deepEqual(
    parseEnvelope(JSON.stringify({ type: 'session', version: id })),
    { type: 'session', version: id }
  );
  for (const invalid of [
    { version: id },
    { type: 'session', version: 'opaque' },
    { ...envelope(request), token: 'synthetic' },
    envelope({ ...request, command: 'synthetic' }),
    envelope({ ...request, action: 'shell' }),
    envelope({ ...request, id: '../path' }),
    envelope({ ...request, actor_id: '42' }),
    envelope({ ...request, actor_id: 0 }),
    envelope({ ...request, actor_id: Number.MAX_SAFE_INTEGER + 1 }),
    envelope({ ...request, created_at: '2026-02-31T10:00:00.000Z' }),
    envelope({ ...request, expires_at: '2026-10-04T12:00:00.000Z' }),
    { ...envelope(), manager: { ...manager, control_available: 'true' } },
    {
      ...envelope(),
      manager: { ...manager, state: 'healthy', control_available: true },
    },
    { ...envelope(), manager: { ...manager, observed_at: 'invalid' } },
  ])
    assert.throws(
      () => parseEnvelope(JSON.stringify(invalid)),
      /publication_failed/
    );
  assert.throws(() => parseEnvelope(' '.repeat(1025)), /publication_failed/);
});

test('typed commands reject extra fields, unsupported operations and client success before transport', () => {
  assert.deepEqual(
    validateRequest({ type: 'operator', operation: 'operator_claim', id }),
    { type: 'operator', operation: 'operator_claim', id }
  );
  for (const invalid of [
    { type: 'operator', operation: 'operator_read', url: 'synthetic' },
    {
      type: 'operator',
      operation: 'operator_complete',
      id,
      state: 'succeeded',
    },
    { type: 'operator', operation: 'exec' },
    {
      type: 'operator',
      operation: 'manager_heartbeat',
      state: 'operator_required',
      control_available: 'true',
    },
    { type: 'operator', operation: 'operator_claim', id: 'x' },
    {
      type: 'operator',
      operation: 'manager_heartbeat',
      state: 'operator_required',
      control_available: true,
      request_id: 'bad',
    },
  ])
    assert.throws(() => validateRequest(invalid), /publication_failed/);
});

test('bootstrap accepts all five canonical values and bounds strings without secrets', () => {
  assert.deepEqual(
    validateRequest({ type: 'session', operation: 'bootstrap' }),
    { type: 'session', operation: 'bootstrap' }
  );
  assert.deepEqual(
    parseEnvelope(JSON.stringify(bootstrap), 'bootstrap'),
    bootstrap
  );
  for (const invalid of [
    { ...bootstrap, metadata: { ...metadata, token: 'synthetic' } },
    {
      ...bootstrap,
      metadata: { ...metadata, INSTAGRAM_TESTER_APP_NAME: 'a'.repeat(121) },
    },
    {
      ...bootstrap,
      metadata: { ...metadata, INSTAGRAM_TESTER_APP_NAME: ' bad' },
    },
    {
      ...bootstrap,
      metadata: { ...metadata, INSTAGRAM_TESTER_ADMIN_USER_ID: 12345 },
    },
    {
      ...bootstrap,
      metadata: { ...metadata, INSTAGRAM_TESTER_APP_NAME: 'bad\nname' },
    },
    { ...bootstrap, revision: 'x' },
  ])
    assert.throws(
      () => parseEnvelope(JSON.stringify(invalid)),
      /publication_failed/
    );
  const config = observerConfiguration(env, bootstrap);
  assert.equal(config.appId, '10001');
  assert.equal(config.adminId, '12345');
  assert.equal(config.docId, '10003');
  assert.equal(config.businessId, '10002');
  assert.equal(config.host, '127.0.0.1');
  assert.throws(() =>
    observerConfiguration(
      { ...env, INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'credentials' },
      bootstrap
    )
  );
});

function waiterHarness(options = {}) {
  const signals = new EventEmitter();
  const events = [];
  let current = { ...request };
  let polls = 0;
  const dependencies = {
    signals,
    now: () => Date.parse(stamp),
    stderr: { write: text => events.push(text) },
    sleep: async () => {
      if (options.stopAfterPoll) signals.emit('SIGTERM');
    },
    publish: async (_command, payload) => {
      events.push(payload);
      validateRequest(payload);
      if (payload.operation === 'bootstrap') return bootstrap;
      if (payload.operation === 'manager_heartbeat') {
        if (!payload.request_id) polls += 1;
        if (options.offline) throw new Error('synthetic offline');
        if (options.stopAfterPoll && polls > 1) signals.emit('SIGTERM');
        return {
          ...envelope(current),
          manager: {
            state: payload.state,
            control_available: payload.control_available,
            observed_at: stamp,
          },
        };
      }
      if (payload.operation === 'operator_claim') {
        current = { ...current, state: 'running' };
        if (options.claimLost) throw new Error('synthetic lost response');
      }
      if (payload.operation === 'operator_complete')
        current = { ...current, state: payload.state };
      return envelope(current);
    },
    child: async (script, childEnv) => {
      const isBrowser = script.endsWith('session-browser.mjs');
      events.push(isBrowser ? 'browser' : 'manager');
      assert.equal(childEnv.INSTAGRAM_META_DEVELOPER_APP_ID, '10001');
      assert.equal(childEnv.INSTAGRAM_TESTER_ADMIN_USER_ID, '12345');
      assert.equal(
        childEnv.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID,
        isBrowser ? undefined : id
      );
      if (options.childFailure) throw new Error('synthetic process failure');
      if (options.shutdown) {
        signals.emit('SIGTERM');
        return 143;
      }
      if (!isBrowser && !options.noPublication && !options.operatorRequired)
        current = { ...current, state: 'succeeded' };
      return options.operatorRequired && !isBrowser ? 2 : 0;
    },
  };
  return { dependencies, events, current: () => current };
}

test('waiter has no session prerequisite, claims before opening browser, shares canonical configuration with manager', async () => {
  const h = waiterHarness();
  await runWaiter(env, h.dependencies);
  const ops = h.events.map(value =>
    typeof value === 'string' ? value : value.operation
  );
  assert.deepEqual(ops, [
    'manager_heartbeat',
    'operator_claim',
    'manager_heartbeat',
    'bootstrap',
    'manager_heartbeat',
    'browser',
    'manager',
    'operator_read',
  ]);
  assert.equal(h.current().state, 'succeeded');
  assert.equal(
    h.events.some(
      value =>
        value.operation === 'operator_complete' && value.state === 'succeeded'
    ),
    false
  );
});

test('process exit zero alone never completes a reconnect successfully', async () => {
  const h = waiterHarness({ noPublication: true, stopAfterPoll: true });
  await runWaiter(env, h.dependencies);
  assert.equal(h.current().state, 'failed');
  assert.equal(h.events.filter(value => value === 'browser').length, 1);
});

test('operator required returns to polling without automatically opening another login', async () => {
  const h = waiterHarness({ operatorRequired: true, stopAfterPoll: true });
  await runWaiter(env, h.dependencies);
  assert.equal(h.current().state, 'operator_required');
  assert.equal(h.events.filter(value => value === 'browser').length, 1);
});

for (const option of ['childFailure', 'claimLost']) {
  test(`${option} fails the claimed request even when transport response is uncertain`, async () => {
    const h = waiterHarness({ [option]: true });
    await assert.rejects(
      runWaiter(env, h.dependencies),
      /operator_runtime_failed/
    );
    assert.equal(h.current().state, 'failed');
    assert.equal(h.events.includes('manager'), false);
  });
}

test('SIGTERM uses independent bounded cleanup to fail a live claim', async () => {
  const h = waiterHarness({ shutdown: true });
  await runWaiter(env, h.dependencies);
  assert.equal(h.current().state, 'failed');
  assert.equal(h.dependencies.signals.listenerCount('SIGTERM'), 0);
});

test('offline gives honest instructions and never opens a browser or manufactures success', async () => {
  const h = waiterHarness({ offline: true, stopAfterPoll: true });
  await runWaiter(env, h.dependencies);
  assert.equal(h.events.includes('browser'), false);
  assert.equal(h.current().state, 'queued');
  assert.equal(
    h.events.some(
      value =>
        typeof value === 'string' && value.includes('no recovery is confirmed')
    ),
    true
  );
});

test('malformed reply never starts a browser', async () => {
  const h = waiterHarness({ stopAfterPoll: true });
  h.dependencies.publish = async () => ({ command: 'synthetic' });
  await runWaiter(env, h.dependencies);
  assert.equal(h.events.includes('browser'), false);
});

test('stubborn runtime child escalates cancellation and settles within 30 seconds', async () => {
  const child = new EventEmitter();
  const killed = [];
  child.kill = signal => killed.push(signal);
  const timers = new Map();
  const clock = {
    setTimeout: (fn, delay) => {
      timers.set(1, { fn, delay });
      return 1;
    },
    clearTimeout: key => timers.delete(key),
  };
  const shutdown = new AbortController();
  const running = runtimeChild('synthetic-script', {}, shutdown.signal, {
    spawnImpl: () => child,
    clock,
  });
  shutdown.abort();
  assert.deepEqual(killed, ['SIGTERM']);
  assert.equal(timers.get(1).delay, 28000);
  timers.get(1).fn();
  assert.equal(await running, 143);
  assert.deepEqual(killed, ['SIGTERM', 'SIGKILL']);
  assert.equal(timers.size, 0);
});

test('publisher never clears sessions or invitation outcomes to unlock reconnect', async () => {
  const source = await readFile(
    new URL(
      '../../scripts/instagram_testers/session_publisher.rb',
      import.meta.url
    ),
    'utf8'
  );
  assert.doesNotMatch(source, /\.invalidate|InvitationOutcome/);
});

test('forced publisher emits only canonical bounded typed replies including bootstrap', async () => {
  const source = await readFile(
    new URL(
      '../../scripts/instagram_testers/runtime/forced-publisher.sh',
      import.meta.url
    ),
    'utf8'
  );
  const synthetic = source
    .replace('/usr/bin/id -u 2>/dev/null', 'printf 0')
    .replace(
      '/usr/bin/docker exec -i chatwoot-web bundle exec rails runner scripts/instagram_testers/session_publisher.rb 2>/dev/null',
      '/bin/cat'
    );
  for (const [reply, code] of [
    [JSON.stringify(envelope(request)), 0],
    [JSON.stringify({ type: 'session', version: id }), 0],
    [JSON.stringify(bootstrap), 0],
    [
      JSON.stringify({
        ...bootstrap,
        metadata: { ...metadata, INSTAGRAM_TESTER_APP_NAME: 'á'.repeat(120) },
      }),
      0,
    ],
    [
      JSON.stringify({
        ...bootstrap,
        metadata: {
          ...metadata,
          INSTAGRAM_TESTER_APP_NAME: 'App "quoted" \\ quoted',
        },
      }),
      0,
    ],
    [JSON.stringify({ version: id }), 2],
    [JSON.stringify(envelope({ ...request, url: 'synthetic' })), 2],
    [
      JSON.stringify({
        ...envelope(),
        manager: { ...manager, state: 'healthy', control_available: true },
      }),
      2,
    ],
    [
      JSON.stringify({
        ...bootstrap,
        metadata: { ...metadata, cookie: 'synthetic' },
      }),
      2,
    ],
    ['x'.repeat(1025), 2],
    [JSON.stringify(envelope()) + '\nlog', 2],
  ]) {
    const result = spawnSync('/bin/sh', ['-c', synthetic], {
      input: reply,
      encoding: 'utf8',
      env: { SUDO_USER: 'chatwoot_publisher' },
    });
    assert.equal(result.status, code, reply);
    assert.equal(result.stdout, code === 0 ? `${reply}\n` : '');
    assert.equal(
      result.stderr,
      code === 0 ? '' : 'instagram_publisher_transport_failed\n'
    );
  }
});

for (const stuckClose of [false, true]) {
  test(`recovery browser SIGTERM releases its lock and signals, stuckClose=${stuckClose}`, async () => {
    const signals = new EventEmitter();
    const timers = new Map();
    let next = 0;
    const clock = {
      setTimeout: (fn, delay) => {
        next += 1;
        timers.set(next, { fn, delay });
        return next;
      },
      clearTimeout: key => timers.delete(key),
    };
    const context = new EventEmitter();
    let opened;
    const ready = new Promise(done => {
      opened = done;
    });
    context.pages = () => [
      {
        goto: async () => {
          opened();
        },
      },
    ];
    context.close = async () => {
      if (stuckClose) return new Promise(() => {});
      context.emit('close');
      return undefined;
    };
    let released = false;
    let unlinked = false;
    const result = recoveryBrowser(
      {
        ...env,
        ...metadata,
        INSTAGRAM_TESTER_PLAYWRIGHT_MODULE: '/synthetic/runtime',
      },
      [],
      {
        signals,
        clock,
        stdout: { write: () => {} },
        files: {
          privateProfile: async path => path,
          open: async () => ({
            close: async () => {
              released = true;
            },
          }),
          unlink: async () => {
            unlinked = true;
          },
        },
        loadRuntime: async () => ({
          chromium: { launchPersistentContext: async () => context },
        }),
      }
    ).catch(error => error);
    await ready;
    for (let step = 0; step < 20; step += 1) await Promise.resolve();
    signals.emit('SIGTERM');
    for (let step = 0; step < 20; step += 1) await Promise.resolve();
    if (stuckClose) {
      const timer = [...timers.values()].find(value => value.delay === 25000);
      assert.ok(timer);
      timer.fn();
    }
    assert.equal((await result).message, 'browser_stopped');
    assert.equal(released, true);
    assert.equal(unlinked, true);
    assert.equal(signals.listenerCount('SIGTERM'), 0);
    assert.equal(timers.size, 0);
  });
}
