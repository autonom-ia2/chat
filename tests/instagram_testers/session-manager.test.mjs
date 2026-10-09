/* eslint-disable no-await-in-loop, no-restricted-syntax -- Synthetic lifecycle cases intentionally serialize process and filesystem operations. */
/* eslint-disable no-promise-executor-return -- The polling promise resolves from setTimeout without exposing its handle. */

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  lstat,
  open,
  readFile,
  realpath,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { configuration } from '../../scripts/instagram_testers/session-observer.mjs';
import {
  run,
  publisher,
  privateProfile,
  managerExitCode,
  isAllowedBrowserRequest,
  handleBrowserRoute,
} from '../../scripts/instagram_testers/session-manager.mjs';

const INITIAL_VERSION = '11111111-1111-4111-8111-111111111111';
const PUBLISHED_VERSION = '22222222-2222-4222-8222-222222222222';
const rolesResponse = `for (;;);${JSON.stringify({
  data: {
    get_app_roles: {
      app_roles: [
        {
          role: 'instagram testers',
          users: [{ id: '10004', status: 'CONFIRMED' }],
        },
      ],
    },
  },
})}`;

const baseEnv = {
  INSTAGRAM_TESTER_APP_NAME: 'Synthetic App',
  INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
  INSTAGRAM_META_BUSINESS_ID: '10002',
  INSTAGRAM_TESTER_ROLES_DOC_ID: '10003',
  INSTAGRAM_TESTER_ADMIN_USER_ID: '12345',
  INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
  INSTAGRAM_TESTER_PROXY_PORT: '9100',
  INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
  INSTAGRAM_TESTER_PROXY_IDENTITY: '93.184.216.34:8080',
};
const loadingDocuments = JSON.parse(
  readFileSync(
    new URL('./fixtures/loading-documents.json', import.meta.url),
    'utf8'
  )
);
const loadingDocumentIds = Object.fromEntries(
  Object.entries(loadingDocuments).map(([name, document]) => [
    name,
    document.doc_id,
  ])
);

const bootstrapMetadata = Object.fromEntries(
  Object.entries(baseEnv).filter(([key]) => !key.includes('PROXY'))
);
const bootstrap = {
  type: 'bootstrap',
  metadata: bootstrapMetadata,
  revision: 'a'.repeat(64),
  version: INITIAL_VERSION,
};

const publisherProgram = [
  "let input = '';",
  "process.stdin.on('data', chunk => { input += chunk; });",
  "process.stdin.on('end', () => {",
  '  const request = JSON.parse(input);',
  "  const fs = require('node:fs');",
  "  fs.appendFileSync(process.env.SYNTHETIC_OPS_FILE, JSON.stringify(request) + '\\n');",
  `  const version = request.operation === 'version' ? '${INITIAL_VERSION}' : request.operation === 'publish' ? '${PUBLISHED_VERSION}' : null;`,
  `  if (request.operation === 'bootstrap') { process.stdout.write(JSON.stringify(${JSON.stringify(bootstrap)})); return; }`,
  '  process.stdout.write(JSON.stringify(request.type === "session" ? { type: "session", version } : { type: "operator", manager: { state: request.state, control_available: request.control_available, observed_at: new Date().toISOString() }, request: null }));',
  '});',
].join('');

const fakeRuntime = `
import { EventEmitter } from 'node:events';
import { appendFileSync } from 'node:fs';

const mode = process.env.SYNTHETIC_MODE || 'valid';
const rolesUrl = 'https://developers.facebook.com/apps/' +
  process.env.INSTAGRAM_META_DEVELOPER_APP_ID + '/roles/roles/?business_id=' +
  process.env.INSTAGRAM_META_BUSINESS_ID;
const body = ${JSON.stringify(rolesResponse)};
const loadingDocumentIds = ${JSON.stringify(loadingDocumentIds)};
const fields = new URLSearchParams({
  __user: process.env.INSTAGRAM_TESTER_ADMIN_USER_ID,
  __bid: process.env.INSTAGRAM_META_BUSINESS_ID,
  doc_id: process.env.INSTAGRAM_TESTER_ROLES_DOC_ID,
  fb_api_req_friendly_name: 'RolesTable_Query',
  variables: JSON.stringify({ app_id: process.env.INSTAGRAM_META_DEVELOPER_APP_ID }),
  fb_dtsg: 'synthetic-dtsg',
  lsd: 'synthetic-lsd',
  jazoest: '1234',
  __req: '1',
  __aaid: '67890',
}).toString();

class Request {
  constructor(requestFields = fields) { this.requestFields = requestFields; }
  url() { return 'https://developers.facebook.com/api/graphql/'; }
  method() { return 'POST'; }
  postData() { return this.requestFields; }
  async allHeaders() {
    return {
      cookie: 'c_user=' + process.env.INSTAGRAM_TESTER_ADMIN_USER_ID + '; xs=synthetic',
      'user-agent': 'Synthetic Browser',
      'x-fb-lsd': 'synthetic-lsd',
    };
  }
}

class Response {
  constructor(status, responseRequest = new Request(), responseBody = body) {
    this.responseStatus = status;
    this.responseRequest = responseRequest;
    this.responseBody = responseBody;
  }
  url() { return 'https://developers.facebook.com/api/graphql/'; }
  request() { return this.responseRequest; }
  status() { return this.responseStatus; }
  async text() {
    if (mode === 'html') process.emit('SIGTERM');
    return mode === 'html' ? '<html>login</html>' : this.responseBody;
  }
}

class Navigation {
  constructor(status) { this.navigationStatus = status; }
  status() { return this.navigationStatus; }
}

class Page extends EventEmitter {
  constructor() {
    super();
    this.currentUrl = rolesUrl;
  }
  url() { return this.currentUrl; }
  async evaluate() { return 200; }
  async goto() {
    if (mode === 'redirect') this.currentUrl = 'https://www.facebook.com/login/';
    if (mode === 'checkpoint-redirect') {
      this.currentUrl = 'https://developers.facebook.com/checkpoint/';
    }
    const responseStatus =
      mode === 'status-401' || mode === 'graphql-401'
        ? 401
        : mode === 'status-403' || mode === 'graphql-403'
          ? 403
          : 200;
    const navigationStatus =
      mode === 'status-401' || mode === 'status-403' ? responseStatus : 200;
    const dispatch = async request => {
      let continued = false;
      let aborted = false;
      await routeHandler({
        request: () => request,
        continue: async () => { continued = true; },
        abort: async () => { aborted = true; },
      });
      appendFileSync(
        process.env.SYNTHETIC_ROUTE_FILE,
        JSON.stringify({
          name: new URLSearchParams(request.postData()).get('fb_api_req_friendly_name'),
          continued,
          aborted,
        }) + '\\n'
      );
      if (!continued || aborted) throw new Error('synthetic_route_not_continued');
    };
    if (mode === 'loading-before-roles') {
      for (const [name, variables] of [
        ['GeoNextAppControllerContainerQuery', { appID: process.env.INSTAGRAM_META_DEVELOPER_APP_ID }],
        ['DeveloperHeaderComponentContainerQuery', {
          businessID: process.env.INSTAGRAM_META_BUSINESS_ID,
          businessID_is_null: false,
        }],
        ['DeveloperAppVisibilityToggleLazyLoadedQuery', { appID: process.env.INSTAGRAM_META_DEVELOPER_APP_ID }],
        ['DeveloperAppBannerQuery', { appID: process.env.INSTAGRAM_META_DEVELOPER_APP_ID }],
        ['DeveloperAppDashboardSidebarNavigationV2Query', { appID: process.env.INSTAGRAM_META_DEVELOPER_APP_ID }],
      ]) {
        const loadingFields = new URLSearchParams({
          __user: process.env.INSTAGRAM_TESTER_ADMIN_USER_ID,
          __bid: process.env.INSTAGRAM_META_BUSINESS_ID,
          av: process.env.INSTAGRAM_TESTER_ADMIN_USER_ID,
          doc_id: loadingDocumentIds[name],
          fb_api_req_friendly_name: name,
          variables: JSON.stringify(variables),
        }).toString();
        const loadingRequest = new Request(loadingFields);
        await dispatch(loadingRequest);
        this.emit('response', new Response(200, loadingRequest, JSON.stringify({
          data: { fetch__Application: { id: process.env.INSTAGRAM_META_DEVELOPER_APP_ID } },
        })));
      }
    }
    const rolesRequest = new Request(fields);
    await dispatch(rolesRequest);
    if (
      ![
        'redirect',
        'checkpoint-redirect',
        'status-401',
        'status-403',
      ].includes(mode)
    ) {
      this.emit('response', new Response(responseStatus, rolesRequest));
    }
    return new Navigation(navigationStatus);
  }
}

let routeHandler;
class Context extends EventEmitter {
  constructor() { super(); this.page = new Page(); }
  pages() { return [this.page]; }
  async newPage() { return this.page; }
  async route(_pattern, handler) { routeHandler = handler; }
  async close() { this.emit('close'); }
}

export const chromium = {
  async launchPersistentContext(profile, options) {
    appendFileSync(
      process.env.SYNTHETIC_LAUNCH_FILE,
      JSON.stringify({ profile, proxy: options.proxy }) + '\\n'
    );
    if (mode === 'proxy-failure') throw new Error('proxy_unavailable');
    return new Context();
  },
};
`;

async function fixture(mode) {
  const root = await mkdtemp(
    join(await realpath(tmpdir()), 'instagram-manager-test-')
  );
  const profile = join(root, 'private-profile');
  const runtime = join(root, 'fake-playwright.mjs');
  const operationLog = join(root, 'operations.jsonl');
  const launch = join(root, 'launch.jsonl');
  const routeLog = join(root, 'routes.jsonl');
  await writeFile(runtime, fakeRuntime, { mode: 0o600 });
  return {
    root,
    operations: operationLog,
    launch,
    routes: routeLog,
    env: {
      ...baseEnv,
      INSTAGRAM_TESTER_BROWSER_PROFILE: profile,
      INSTAGRAM_TESTER_PLAYWRIGHT_MODULE: runtime,
      INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: JSON.stringify([
        process.execPath,
        '-e',
        publisherProgram,
      ]),
    },
    processEnv: {
      SYNTHETIC_MODE: mode,
      SYNTHETIC_OPS_FILE: operationLog,
      SYNTHETIC_LAUNCH_FILE: launch,
      SYNTHETIC_ROUTE_FILE: routeLog,
      ...baseEnv,
    },
  };
}

async function readOperations(path) {
  try {
    const text = await readFile(path, 'utf8');
    return text
      .trim()
      .split('\n')
      .filter(Boolean)
      .map(line => JSON.parse(line));
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

async function waitForOperation(path, operation) {
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const entries = await readOperations(path);
    if (entries.some(entry => entry.operation === operation)) return entries;
    await new Promise(resolve => {
      setTimeout(resolve, 10);
    });
  }
  throw new Error(`Synthetic operation not observed: ${operation}`);
}

async function withProcessEnv(values, action) {
  const previous = new Map(
    Object.keys(values).map(key => [key, process.env[key]])
  );
  Object.assign(process.env, values);
  try {
    return await action();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function cleanup(fixtureData) {
  await rm(fixtureData.root, { recursive: true, force: true });
}

test('publishes one observed session with the expected version and proxy binding', async () => {
  const data = await fixture('valid');
  let settled;
  try {
    settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const entries = await waitForOperation(data.operations, 'publish');
    process.emit('SIGTERM');
    const error = await settled;
    assert.equal(error, null);
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['bootstrap', 'publish']
    );
    const publication = entries[1];
    assert.equal(publication.expected_version, INITIAL_VERSION);
    assert.equal(
      publication.proxy_fingerprint,
      configuration(data.env).proxyFingerprint
    );
    assert.equal(
      publication.session.user_id,
      baseEnv.INSTAGRAM_TESTER_ADMIN_USER_ID
    );
    assert.equal(publication.app_id, baseEnv.INSTAGRAM_META_DEVELOPER_APP_ID);
  } finally {
    process.emit('SIGTERM');
    if (settled) await settled;
    await cleanup(data);
  }
});

test('allows pinned loading queries before RolesTable and publishes exactly once from RolesTable', async () => {
  const data = await fixture('loading-before-roles');
  let settled;
  try {
    settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const entries = await waitForOperation(data.operations, 'publish');
    process.emit('SIGTERM');
    const error = await settled;
    assert.equal(error, null);
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['bootstrap', 'publish']
    );
    const routes = await readOperations(data.routes);
    assert.deepEqual(
      routes.map(route => route.name),
      [
        'GeoNextAppControllerContainerQuery',
        'DeveloperHeaderComponentContainerQuery',
        'DeveloperAppVisibilityToggleLazyLoadedQuery',
        'DeveloperAppBannerQuery',
        'DeveloperAppDashboardSidebarNavigationV2Query',
        'RolesTable_Query',
      ]
    );
    assert.equal(
      routes.every(route => route.continued && !route.aborted),
      true
    );
  } finally {
    process.emit('SIGTERM');
    if (settled) await settled;
    await cleanup(data);
  }
});

for (const status of [401, 403]) {
  test(`preserves the stored version and stops on HTTP ${status}`, async () => {
    const data = await fixture(`status-${status}`);
    try {
      const settled = withProcessEnv(data.processEnv, () =>
        run(data.env).then(
          () => null,
          error => error
        )
      );
      const error = await settled;
      const entries = await readOperations(data.operations);
      assert.equal(error?.message, 'operator_required');
      assert.deepEqual(
        entries.map(entry => entry.operation),
        ['bootstrap', 'manager_heartbeat']
      );
      assert.equal(entries[1].state, 'operator_required');
      assert.equal(entries[1].control_available, false);
    } finally {
      process.emit('SIGTERM');
      await cleanup(data);
    }
  });
}

for (const status of [401, 403]) {
  test(`requests intervention on GraphQL response HTTP ${status} with healthy navigation`, async () => {
    const data = await fixture(`graphql-${status}`);
    try {
      const settled = withProcessEnv(data.processEnv, () =>
        run(data.env).then(
          () => null,
          error => error
        )
      );
      const error = await settled;
      const entries = await readOperations(data.operations);
      assert.equal(error?.message, 'operator_required');
      assert.deepEqual(
        entries.map(entry => entry.operation),
        ['bootstrap', 'manager_heartbeat']
      );
      assert.equal(entries[1].state, 'operator_required');
      assert.equal(entries[1].control_available, false);
    } finally {
      process.emit('SIGTERM');
      await cleanup(data);
    }
  });
}

test('preserves session and stops on a login redirect without a direct HTTP fallback', async () => {
  const data = await fixture('redirect');
  try {
    const settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const error = await settled;
    const entries = await readOperations(data.operations);
    assert.equal(error?.message, 'operator_required');
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['bootstrap', 'manager_heartbeat']
    );
    assert.equal(entries[1].control_available, false);
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

test('preserves session and stops on a checkpoint or two-factor redirect', async () => {
  const data = await fixture('checkpoint-redirect');
  try {
    const settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const error = await settled;
    const entries = await readOperations(data.operations);
    assert.equal(error?.message, 'operator_required');
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['bootstrap', 'manager_heartbeat']
    );
    assert.equal(entries[1].control_available, false);
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

test('SIGTERM during response body stops without invalidating the current version', async () => {
  const data = await fixture('html');
  try {
    const settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const error = await settled;
    const entries = await readOperations(data.operations);
    assert.equal(error, null);
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['bootstrap']
    );
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

test('fails closed when the proxy browser cannot launch and never falls back direct', async () => {
  const data = await fixture('proxy-failure');
  try {
    const settled = withProcessEnv(data.processEnv, () =>
      run(data.env).then(
        () => null,
        error => error
      )
    );
    const error = await settled;
    const entries = await readOperations(data.operations);
    const launches = JSON.parse((await readFile(data.launch, 'utf8')).trim());
    assert.equal(error?.message, 'proxy_unavailable');
    assert.deepEqual(entries, []);
    assert.deepEqual(launches.proxy, { server: 'http://127.0.0.1:9100' });
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

async function drain() {
  for (let index = 0; index < 20; index += 1) await Promise.resolve();
}

class FakeClock {
  constructor() {
    this.time = 0;
    this.next = 0;
    this.timers = new Map();
  }

  setTimeout(callback, milliseconds) {
    this.next += 1;
    const id = this.next;
    this.timers.set(id, { at: this.time + milliseconds, callback });
    return id;
  }

  clearTimeout(id) {
    this.timers.delete(id);
  }

  async advance(milliseconds) {
    const end = this.time + milliseconds;
    while (this.timers.size) {
      const next = [...this.timers.entries()]
        .filter(([, timer]) => timer.at <= end)
        .sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      this.time = next[1].at;
      this.timers.delete(next[0]);
      next[1].callback();
      await drain();
    }
    this.time = end;
    await drain();
  }
}

function deferred() {
  let resolvePromise;
  let rejectPromise;
  const promise = new Promise((resolveValue, rejectValue) => {
    resolvePromise = resolveValue;
    rejectPromise = rejectValue;
  });
  return { promise, resolve: resolvePromise, reject: rejectPromise };
}

async function syntheticManager(t, options = {}) {
  const data = await fixture('valid');
  if (options.vps) {
    data.env.INSTAGRAM_TESTER_RUNTIME_MODE = 'vps';
    data.env.INSTAGRAM_TESTER_CHROMIUM_SANDBOX = 'true';
  }
  if (options.browserOperations)
    data.env.INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED = 'true';
  if (options.reconnectId)
    data.env.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID = options.reconnectId;
  const clock = new FakeClock();
  const signals = new EventEmitter();
  const entries = [];
  const bodies = [];
  const headers = [];
  const stdout = [];
  const stderr = [];
  const launched = deferred();
  const config = configuration(data.env);
  const fields = new URLSearchParams({
    __user: baseEnv.INSTAGRAM_TESTER_ADMIN_USER_ID,
    __bid: baseEnv.INSTAGRAM_META_BUSINESS_ID,
    doc_id: baseEnv.INSTAGRAM_TESTER_ROLES_DOC_ID,
    fb_api_req_friendly_name: 'RolesTable_Query',
    variables: JSON.stringify({
      app_id: baseEnv.INSTAGRAM_META_DEVELOPER_APP_ID,
    }),
    fb_dtsg: 'synthetic-dtsg',
    lsd: 'synthetic-lsd',
    jazoest: '1234',
    __req: '1',
    __aaid: '67890',
  }).toString();
  const request = {
    url: () => 'https://developers.facebook.com/api/graphql/',
    method: () => 'POST',
    postData: () => fields,
    allHeaders: () => {
      const value = deferred();
      headers.push(value);
      if (!options.pendingHeaders)
        value.resolve({
          cookie: 'c_user=12345; xs=synthetic',
          'user-agent': 'Synthetic Browser',
          'x-fb-lsd': 'synthetic-lsd',
        });
      return value.promise;
    },
  };
  const page = new EventEmitter();
  let navigations = 0;
  let routeHandler;
  page.url = () => options.redirect || config.rolesUrl;
  page.isClosed = () => options.closedPrimary === true;
  page.evaluate = async () => 200;
  page.close = async () => {
    options.closedPrimary = true;
  };
  const navigated = [];
  page.goto = async url => {
    navigated.push(url);
    navigations += 1;
    let continued = false;
    await routeHandler({
      request: () => request,
      continue: async () => {
        continued = true;
      },
      abort: async () => {
        throw new Error('synthetic_browser_gate_rejected');
      },
    });
    assert.equal(continued, true);
    if (options.pendingNavigation) return new Promise(() => {});
    if (options.backgroundMethod) {
      page.emit('response', {
        url: request.url,
        request: () => ({
          ...request,
          method: () => options.backgroundMethod,
          postData: () => options.backgroundBody ?? null,
          allHeaders: options.backgroundHeaders,
        }),
        status: () => 200,
        text: async () => '',
      });
    }
    const body = deferred();
    bodies.push(body);
    if (!options.pendingBody) body.resolve(rolesResponse);
    page.emit('response', {
      url: request.url,
      request: () => request,
      status: () => options.status || 200,
      text: () => body.promise,
    });
    return { status: () => 200 };
  };
  let closed = 0;
  const context = new EventEmitter();
  context.pages = () => [page];
  context.route = async (_pattern, handler) => {
    routeHandler = handler;
    launched.resolve();
  };
  context.close = async () => {
    closed += 1;
    if (options.pendingClose) await new Promise(() => {});
  };
  let versionReads = 0;
  let currentVersion = options.initialVersion || null;
  let publications = 0;
  const browserRequest = options.browserRequest || {
    type: 'browser_operation',
    operation: 'request',
    id: '33333333-3333-4333-8333-333333333333',
    request_id: '44444444-4444-4444-8444-444444444444',
    claim: '55555555-5555-4555-8555-555555555555',
    action: 'search',
    app_id: baseEnv.INSTAGRAM_META_DEVELOPER_APP_ID,
    username: 'synthetic.user',
    deadline: '2999-01-01T00:00:00.000Z',
  };
  const pendingPublish = deferred();
  const pendingInvalidation = deferred();
  const cleanupWaiting = deferred();
  let unlinkStarted = false;
  const releaseUnlink = deferred();
  const unlinkCompleted = deferred();
  // A failed IO receipt remains observable without an unhandled rejection.
  unlinkCompleted.promise.catch(() => {});
  const settled = run(data.env, {
    clock,
    now: () => clock.time,
    signals,
    files: {
      privateProfile,
      open: async (...args) => {
        const handle = await open(...args);
        return {
          close: async () => {
            await handle.close();
            if (options.pendingLockClose) {
              cleanupWaiting.resolve();
              await new Promise(() => {});
            }
          },
        };
      },
      unlink: async path => {
        unlinkStarted = true;
        try {
          if (options.deferUnlink) await releaseUnlink.promise;
          await unlink(path);
          unlinkCompleted.resolve();
        } catch (error) {
          unlinkCompleted.reject(error);
          throw error;
        }
        if (options.pendingUnlink) {
          cleanupWaiting.resolve();
          await new Promise(() => {});
        }
      },
    },
    stdout: { write: text => stdout.push(text) },
    stderr: { write: text => stderr.push(text) },
    loadRuntime: async () => ({
      chromium: {
        launchPersistentContext: async () => context,
      },
    }),
    executeOperation: options.executeOperation,
    publish: async (_command, payload, { signal }) => {
      entries.push({ payload, signal, at: clock.time });
      signal.throwIfAborted();
      if (payload.operation === 'bootstrap') {
        versionReads += 1;
        if (options.failVersion === versionReads)
          throw new Error('publication_failed');
        if (options.pendingVersion) return new Promise(() => {});
        const latest =
          options.changedMetadata && versionReads > 1
            ? {
                ...bootstrap,
                metadata: { ...bootstrap.metadata, ...options.changedMetadata },
                revision: 'b'.repeat(64),
              }
            : bootstrap;
        return { ...latest, version: currentVersion };
      }
      if (payload.type === 'operator') {
        if (
          options.pendingInvalidation &&
          payload.state === 'operator_required'
        )
          return pendingInvalidation.promise;
        return {
          type: 'operator',
          manager: {
            state: payload.state,
            control_available: payload.control_available,
            observed_at: new Date(clock.time).toISOString(),
          },
          request: null,
        };
      }
      if (payload.type === 'browser_operation') {
        const publishDelay = options.browserPublishDelayMs?.[payload.operation];
        if (publishDelay)
          await new Promise((resolveDelay, rejectDelay) => {
            const timer = clock.setTimeout(resolveDelay, publishDelay);
            signal.addEventListener(
              'abort',
              () => {
                clock.clearTimeout(timer);
                rejectDelay(signal.reason);
              },
              { once: true }
            );
          });
        if (payload.operation === 'invite_permit') {
          // Like the real publishers, a pending permit settles only on abort.
          if (options.pendingPermit)
            return new Promise((_resolvePermit, rejectPermit) => {
              signal.addEventListener(
                'abort',
                () => rejectPermit(signal.reason),
                { once: true }
              );
            });
          return {
            type: 'browser_operation',
            operation: 'invite_permit',
            id: payload.id,
            request_id: payload.request_id,
            claim: payload.claim,
            decision: 'write',
            status: 'absent',
          };
        }
        if (payload.operation === 'read')
          return {
            type: 'browser_operation',
            operation: 'read',
            request:
              clock.time >= (options.browserRequestReadyAt ?? 1000)
                ? browserRequest
                : null,
          };
        if (payload.operation === 'claim')
          return {
            type: 'browser_operation',
            operation: 'claim',
            request: browserRequest,
          };
        if (payload.operation === 'complete')
          return {
            type: 'browser_operation',
            operation: 'complete',
            id: payload.id,
            request_id: payload.request_id,
          };
      }
      publications += 1;
      if (options.rejectPublication === publications) {
        currentVersion = '00000000-0000-4000-8000-999999999999';
        throw new Error('publication_failed');
      }
      if (options.pendingPublish) return pendingPublish.promise;
      currentVersion = `00000000-0000-4000-8000-${String(publications).padStart(12, '0')}`;
      return currentVersion;
    },
  }).then(
    () => null,
    error => error
  );
  await launched.promise;
  await drain();
  t.after(async () => {
    signals.emit('SIGTERM');
    await drain();
    await clock.advance(30000);
    await settled;
    releaseUnlink.resolve();
    if (unlinkStarted) await unlinkCompleted.promise.catch(() => {});
    await cleanup(data);
  });
  return {
    get unlinkStarted() {
      return unlinkStarted;
    },
    unlinkCompleted: unlinkCompleted.promise,
    releaseUnlink: releaseUnlink.resolve,
    clock,
    signals,
    entries,
    browserRequest,
    bodies,
    headers,
    stdout,
    stderr,
    settled,
    pendingPublish,
    pendingInvalidation,
    cleanupWaiting,
    page,
    route: (...args) => routeHandler(...args),
    navigated,
    navigations: () => navigations,
    closed: () => closed,
    lockPath: join(
      data.env.INSTAGRAM_TESTER_BROWSER_PROFILE,
      '.instagram-manager.lock'
    ),
  };
}

test('polls browser operations at 250 ms and executes a queued request once', async t => {
  const executions = [];
  let observedWarm;
  const data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    browserRequestReadyAt: 249,
    executeOperation: async ({ request, page, warmMetaPage }) => {
      assert.equal(warmMetaPage.valid, true);
      assert.equal(warmMetaPage.page, page);
      assert.equal(warmMetaPage.source, 'manager_refresh');
      assert.equal(warmMetaPage.rolesAaid, '67890');
      observedWarm = warmMetaPage;
      executions.push(request);
      return {
        type: 'browser_operation',
        operation: 'complete',
        action: request.action,
        id: request.id,
        request_id: request.request_id,
        claim: request.claim,
        captured_at: '2026-10-08T12:00:00.000Z',
        results: [],
      };
    },
  });
  const browserEntries = () =>
    data.entries.filter(entry => entry.payload.type === 'browser_operation');
  try {
    await data.clock.advance(249);
    assert.equal(executions.length, 0);
    assert.equal(
      browserEntries().filter(entry => entry.payload.operation === 'claim')
        .length,
      0
    );

    await data.clock.advance(1);
    const reads = browserEntries().filter(
      entry => entry.payload.operation === 'read'
    );
    const claims = browserEntries().filter(
      entry => entry.payload.operation === 'claim'
    );
    const completions = browserEntries().filter(
      entry => entry.payload.operation === 'complete'
    );
    assert.deepEqual(
      reads.map(entry => entry.at),
      [0, 250]
    );
    assert.equal(claims.length, 1);
    assert.equal(completions.length, 1);
    assert.equal(executions.length, 1);
    assert.equal(observedWarm.disposed, false);
    assert.equal(
      data.entries.filter(entry => entry.payload.operation === 'bootstrap')
        .length,
      1
    );
    assert.equal(
      data.entries.filter(entry => entry.payload.operation === 'authorization')
        .length,
      0
    );
    data.signals.emit('SIGTERM');
    assert.equal(await data.settled, null);
    assert.equal(observedWarm.disposed, true);
    assert.equal(observedWarm.valid, false);
    assert.equal(observedWarm.formBody, null);
  } finally {
    data.signals.emit('SIGTERM');
  }
});

test('three refresh cycles preserve opaque CAS versions and the 15-minute interval', async t => {
  const data = await syntheticManager(t);
  assert.equal(data.navigations(), 1);
  await data.clock.advance(900000);
  await data.clock.advance(900000);
  const writes = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.deepEqual(
    writes.map(entry => entry.payload.expected_version),
    [
      null,
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000002',
    ]
  );
  assert.deepEqual(
    writes.map(entry => entry.at),
    [0, 900000, 1800000]
  );
  data.signals.emit('SIGTERM');
  assert.equal(await data.settled, null);
  assert.equal(data.closed(), 1);
});

for (const failVersion of [1, 2]) {
  test(`version failure in cycle ${failVersion} recovers without aggressive retry`, async t => {
    const data = await syntheticManager(t, { failVersion });
    if (failVersion === 2) await data.clock.advance(900000);
    const reads = data.entries.filter(
      entry => entry.payload.operation === 'bootstrap'
    ).length;
    await data.clock.advance(899999);
    assert.equal(
      data.entries.filter(entry => entry.payload.operation === 'bootstrap')
        .length,
      reads
    );
    await data.clock.advance(1);
    assert.equal(data.stdout.includes('instagram_session_recovered\n'), true);
    assert.equal(data.stderr.length, 1);
    data.signals.emit('SIGTERM');
    assert.equal(await data.settled, null);
  });
}

for (const pending of [
  'pendingHeaders',
  'pendingBody',
  'pendingPublish',
  'pendingVersion',
  'pendingNavigation',
]) {
  test(`whole-cycle deadline cancels ${pending} and permits the next cycle`, async t => {
    const data = await syntheticManager(t, { [pending]: true });
    await data.clock.advance(30000);
    assert.equal(data.entries[0].signal.aborted, true);
    assert.equal(data.page.listenerCount('response'), 0);
    assert.deepEqual(data.stderr, [
      'instagram_session_session_update_rejected\n',
    ]);
    const count = data.entries.length;
    data.bodies[0]?.resolve(rolesResponse);
    data.headers[0]?.resolve({ cookie: 'c_user=12345; xs=synthetic' });
    data.pendingPublish.resolve('late-generation');
    await drain();
    assert.equal(data.entries.length, count);
    await data.clock.advance(900000);
    assert.equal(
      data.entries.filter(entry => entry.payload.operation === 'bootstrap')
        .length,
      2
    );
    data.signals.emit('SIGTERM');
    assert.equal(await data.settled, null);
  });
}

for (const pending of [
  'pendingHeaders',
  'pendingBody',
  'pendingPublish',
  'pendingVersion',
  'pendingNavigation',
]) {
  test(`SIGTERM cancels ${pending}, removes lock, and rejects stale completion`, async t => {
    const data = await syntheticManager(t, { [pending]: true });
    data.signals.emit('SIGTERM');
    assert.equal(await data.settled, null);
    assert.equal(data.closed(), 1);
    assert.equal(data.entries[0].signal.aborted, true);
    await assert.rejects(readFile(data.lockPath), { code: 'ENOENT' });
    const count = data.entries.length;
    data.bodies[0]?.resolve(rolesResponse);
    data.headers[0]?.resolve({ cookie: 'c_user=12345; xs=synthetic' });
    data.pendingPublish.resolve('late-generation');
    await drain();
    await data.clock.advance(1800000);
    assert.equal(data.entries.length, count);
    assert.equal(data.signals.listenerCount('SIGTERM'), 0);
    assert.equal(data.clock.timers.size, 0);
  });
}

test(
  'cleanup has a deadline even when browser close never resolves',
  { timeout: 3000 },
  async t => {
    const data = await syntheticManager(t, {
      pendingBody: true,
      pendingClose: true,
    });
    data.signals.emit('SIGTERM');
    await drain();
    assert.equal(data.closed(), 1);
    await data.clock.advance(30000);
    assert.equal(await data.settled, null);
    assert.equal(data.unlinkStarted, true);
    assert.equal(data.signals.listenerCount('SIGTERM'), 0);
    assert.equal(data.signals.listenerCount('SIGINT'), 0);
    assert.equal(data.clock.timers.size, 0);
    await data.unlinkCompleted;
    await assert.rejects(readFile(data.lockPath), { code: 'ENOENT' });
  }
);

test(
  'cleanup deadline returns before deferred filesystem unlink completes',
  { timeout: 3000 },
  async t => {
    const data = await syntheticManager(t, {
      pendingBody: true,
      pendingClose: true,
      deferUnlink: true,
    });
    data.signals.emit('SIGTERM');
    await drain();
    assert.equal(data.closed(), 1);
    await data.clock.advance(30000);
    assert.equal(await data.settled, null);
    assert.equal(data.unlinkStarted, true);
    assert.equal(data.signals.listenerCount('SIGTERM'), 0);
    assert.equal(data.signals.listenerCount('SIGINT'), 0);
    assert.equal(data.clock.timers.size, 0);
    // IO is deliberately blocked while the manager has already returned.
    await readFile(data.lockPath);
    data.releaseUnlink();
    await data.unlinkCompleted;
    await assert.rejects(readFile(data.lockPath), { code: 'ENOENT' });
  }
);

for (const redirect of [
  'https://www.facebook.com/login/',
  'https://developers.facebook.com/checkpoint/',
  'https://www.facebook.com/two_factor/',
]) {
  test(`operator redirect ${new URL(redirect).pathname} remains terminal with no retries`, async t => {
    const data = await syntheticManager(t, { redirect });
    assert.equal((await data.settled)?.message, 'operator_required');
    await data.clock.advance(1800000);
    assert.equal(data.navigations(), 1);
    assert.equal(
      data.entries.some(entry => entry.payload.operation === 'publish'),
      false
    );
  });
}

test('exit code 2 is exclusive to operator_required; operational errors restart', () => {
  assert.equal(managerExitCode(new Error('operator_required')), 2);
  assert.equal(managerExitCode(new Error('publication_failed')), 1);
  assert.equal(managerExitCode(new Error('proxy_unavailable')), 1);
});

test('publisher cancellation kills synthetic child without waiting for exit', async () => {
  const clock = new FakeClock();
  const controller = new AbortController();
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stdin = new EventEmitter();
  let killed = 0;
  child.kill = () => {
    killed += 1;
  };
  child.stdin.end = () => {};
  const result = publisher(
    ['synthetic-child'],
    { type: 'session', operation: 'version' },
    {
      signal: controller.signal,
      clock,
      spawnImpl: () => child,
    }
  );
  controller.abort(new Error('manager_stopped'));
  await assert.rejects(result, { message: 'manager_stopped' });
  assert.equal(killed, 1);
  child.stdout.emit(
    'data',
    JSON.stringify({ type: 'session', version: PUBLISHED_VERSION })
  );
  child.emit('exit', 0);
  child.emit('close', 0);
  assert.equal(clock.timers.size, 0);
});

test('browser gate stays closed to mutations and untrusted destinations', () => {
  const config = configuration(baseEnv);
  for (const url of [
    'https://attacker.example/',
    'http://developers.facebook.com/',
    'https://developers.facebook.com/roles/add/',
  ]) {
    assert.equal(
      isAllowedBrowserRequest({ url, method: 'GET', config }),
      false
    );
  }
  assert.equal(
    isAllowedBrowserRequest({
      url: 'https://developers.facebook.com/api/graphql/',
      method: 'POST',
      body: new URLSearchParams({
        fb_api_req_friendly_name: 'Mutation',
      }).toString(),
      config,
    }),
    false
  );
});

test('a hung invalidation still stops for operator_required at the cycle deadline', async t => {
  const data = await syntheticManager(t, {
    initialVersion: INITIAL_VERSION,
    redirect: 'https://www.facebook.com/two_factor/',
    pendingInvalidation: true,
  });
  await data.clock.advance(30000);
  assert.equal((await data.settled)?.message, 'operator_required');
  assert.equal(
    data.entries.filter(
      entry =>
        entry.payload.operation === 'manager_heartbeat' &&
        entry.payload.state === 'operator_required'
    ).length,
    1
  );
  await data.clock.advance(1800000);
  assert.equal(data.navigations(), 1);
  assert.equal(
    data.entries.some(entry => entry.payload.operation === 'publish'),
    false
  );
});

test('an old body completing during a new cycle cannot publish the old capture', async t => {
  const data = await syntheticManager(t, { pendingBody: true });
  await data.clock.advance(30000);
  await data.clock.advance(900000);
  assert.equal(data.bodies.length, 2);
  data.bodies[0].resolve(rolesResponse);
  await drain();
  assert.equal(
    data.entries.some(entry => entry.payload.operation === 'publish'),
    false
  );
  data.bodies[1].resolve(rolesResponse);
  await drain();
  const publications = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.equal(publications.length, 1);
  assert.equal(
    publications[0].payload.captured_at,
    new Date(930000).toISOString()
  );
});

test('CAS rejection reads the revocation revision and captures again on the next refresh', async t => {
  const data = await syntheticManager(t, {
    initialVersion: INITIAL_VERSION,
    rejectPublication: 1,
  });
  await data.clock.advance(900000);
  const writes = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.deepEqual(
    writes.map(entry => entry.payload.expected_version),
    [INITIAL_VERSION, '00000000-0000-4000-8000-999999999999']
  );
  assert.notEqual(writes[0].payload.captured_at, writes[1].payload.captured_at);
  assert.equal(data.navigations(), 2);
  assert.deepEqual(data.stdout, ['instagram_session_recovered\n']);
});

for (const pending of ['pendingLockClose', 'pendingUnlink']) {
  test(`cleanup deadline bounds ${pending} and releases signal listeners`, async t => {
    const data = await syntheticManager(t, { [pending]: true });
    data.signals.emit('SIGTERM');
    await drain();
    await data.cleanupWaiting.promise;
    await drain();
    await data.clock.advance(30000);
    assert.equal(await data.settled, null);
    assert.equal(data.signals.listenerCount('SIGTERM'), 0);
    assert.equal(data.clock.timers.size, 0);
  });
}

test('recovery manager exits only after its first CAS receipt so the wrapper can start continuous refresh', async t => {
  const data = await syntheticManager(t, { reconnectId: INITIAL_VERSION });
  assert.equal(await data.settled, null);
  await data.clock.advance(900000);
  const writes = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.equal(writes.length, 1);
  assert.equal(writes[0].payload.request_id, INITIAL_VERSION);
  const heartbeats = data.entries.filter(
    entry => entry.payload.operation === 'manager_heartbeat'
  );
  assert.equal(heartbeats.length, 1);
  assert.equal(heartbeats[0].payload.state, 'healthy');
  assert.equal(data.closed(), 1);
});

test('a changed canonical App/admin is used by the next cycle and rejects the old observed request', async t => {
  const data = await syntheticManager(t, {
    changedMetadata: {
      INSTAGRAM_META_DEVELOPER_APP_ID: '20001',
      INSTAGRAM_TESTER_ADMIN_USER_ID: '54321',
    },
  });
  await data.clock.advance(900000);
  const writes = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.equal(writes.length, 1);
  assert.equal(writes[0].payload.configuration_revision, 'a'.repeat(64));
  assert.equal(writes[0].payload.roles_doc_id, '10003');
  assert.equal(
    data.navigated[1],
    'https://developers.facebook.com/apps/20001/roles/roles/?business_id=10002'
  );
  assert.equal(
    data.stderr.includes('instagram_session_session_update_rejected\n'),
    true
  );
});

test('shared cleanup deadline bounds several stuck cleanup operations together to 25s before child SIGKILL at28s', async t => {
  const data = await syntheticManager(t, {
    pendingClose: true,
    pendingLockClose: true,
    pendingUnlink: true,
  });
  data.signals.emit('SIGTERM');
  await drain();
  await data.clock.advance(25000);
  assert.equal(await data.settled, null);
  assert.equal(data.signals.listenerCount('SIGTERM'), 0);
  assert.equal(data.clock.timers.size, 0);
});

for (const step of ['loadRuntime', 'launch', 'route']) {
  test(`30s deadline bounds startup at ${step} and preserves resources owned by other processes`, async () => {
    const clock = new FakeClock();
    const signals = new EventEmitter();
    let released = false;
    let unlinked = false;
    const context = new EventEmitter();
    const page = new EventEmitter();
    context.pages = () => [page];
    context.route = async () => {
      if (step === 'route') return new Promise(() => {});
      return undefined;
    };
    context.close = async () => {};
    const result = run(
      {
        ...baseEnv,
        INSTAGRAM_TESTER_BROWSER_PROFILE: '/synthetic/private',
        INSTAGRAM_TESTER_PLAYWRIGHT_MODULE: '/synthetic/runtime',
        INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: '["synthetic"]',
      },
      {
        clock,
        signals,
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
        loadRuntime: async () => {
          if (step === 'loadRuntime') return new Promise(() => {});
          return {
            chromium: {
              launchPersistentContext: async () =>
                step === 'launch' ? new Promise(() => {}) : context,
            },
          };
        },
        publish: async () => assert.fail('no transport before bootstrap'),
      }
    ).catch(error => error);
    await drain();
    await clock.advance(30000);
    assert.equal((await result).message, 'operation_timeout');
    assert.equal(released, true);
    assert.equal(unlinked, true);
    assert.equal(signals.listenerCount('SIGTERM'), 0);
  });
}

test('failed profile lock acquisition never removes another process lock', async () => {
  const clock = new FakeClock();
  const signals = new EventEmitter();
  await assert.rejects(
    run(
      { ...baseEnv, INSTAGRAM_TESTER_BROWSER_PROFILE: '/synthetic/private' },
      {
        clock,
        signals,
        files: {
          privateProfile: async path => path,
          open: async () => {
            throw new Error('foreign_lock');
          },
          unlink: async () => assert.fail('foreign lock removed'),
        },
      }
    ),
    /foreign_lock/
  );
  assert.equal(signals.listenerCount('SIGTERM'), 0);
  assert.equal(clock.timers.size, 0);
});

const emojiBootstrap = {
  type: 'bootstrap',
  metadata: {
    INSTAGRAM_META_DEVELOPER_APP_ID: '1',
    INSTAGRAM_META_BUSINESS_ID: '1',
    INSTAGRAM_TESTER_APP_NAME: '😀'.repeat(120),
    INSTAGRAM_TESTER_ADMIN_USER_ID: '1',
    INSTAGRAM_TESTER_ROLES_DOC_ID: '1',
  },
  revision: 'a'.repeat(64),
  version: null,
};
for (const exitFirst of [false, true]) {
  test(`publisher waits for close and decodes split 781-byte UTF8 bootstrap; exitFirst=${exitFirst}`, async () => {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stdin = new EventEmitter();
    child.stdin.end = () => {};
    child.kill = () => {};
    const result = publisher(
      ['synthetic'],
      { type: 'session', operation: 'bootstrap' },
      { spawnImpl: () => child }
    );
    const bytes = Buffer.from(JSON.stringify(emojiBootstrap));
    assert.equal(bytes.length, 781);
    const split = bytes.indexOf(Buffer.from('😀')) + 1;
    if (exitFirst) child.emit('exit', 0);
    child.stdout.emit('data', bytes.subarray(0, split));
    child.stdout.emit('data', bytes.subarray(split));
    if (!exitFirst) child.emit('exit', 0);
    child.emit('close', 0);
    assert.deepEqual(await result, emojiBootstrap);
  });
}
for (const failure of ['overflow', 'error', 'abort', 'deadline', 'nonzero']) {
  test(`publisher rejects ${failure} after exit and never accepts later close`, async () => {
    const clock = new FakeClock();
    const shutdown = new AbortController();
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stdin = new EventEmitter();
    child.stdin.end = () => {};
    child.kill = () => {};
    const result = publisher(
      ['synthetic'],
      { type: 'session', operation: 'bootstrap' },
      { clock, signal: shutdown.signal, spawnImpl: () => child }
    );
    const rejected = assert.rejects(result);
    child.emit('exit', 0);
    child.stdout.emit('data', Buffer.from(JSON.stringify(emojiBootstrap)));
    if (failure === 'overflow')
      child.stdout.emit('data', Buffer.alloc(244, 32));
    if (failure === 'error') child.emit('error', new Error('synthetic'));
    if (failure === 'abort') shutdown.abort(new Error('synthetic'));
    if (failure === 'deadline') await clock.advance(30000);
    child.emit('close', failure === 'nonzero' ? 1 : 0);
    await rejected;
    assert.equal(clock.timers.size, 0);
  });
}

test('VPS cadence leaves room for its full cycle before the backend heartbeat expires', async t => {
  const data = await syntheticManager(t, { vps: true });
  await data.clock.advance(780000);
  await data.clock.advance(780000);
  const writes = data.entries.filter(
    entry => entry.payload.operation === 'publish'
  );
  assert.deepEqual(
    writes.map(entry => entry.at),
    [0, 780000, 1560000]
  );
  assert.ok(780000 + 120000 < 960000);
  data.signals.emit('SIGTERM');
  assert.equal(await data.settled, null);
});

for (const [method, body, label] of [
  ['GET', null, 'GET'],
  ['HEAD', null, 'HEAD'],
  ['POST', 'fb_api_req_friendly_name=OtherRead_Query', 'unrelated POST'],
  [
    'POST',
    'fb_api_req_friendly_name=RolesTable_Query&doc_id=invalid',
    'invalid roles POST',
  ],
]) {
  test(`ignores background ${label} GraphQL before reserving a roles publication`, async t => {
    let backgroundHeaderReads = 0;
    const data = await syntheticManager(t, {
      backgroundMethod: method,
      backgroundBody: body,
      backgroundHeaders: () => {
        backgroundHeaderReads += 1;
        return new Promise(() => {});
      },
    });
    assert.equal(backgroundHeaderReads, 0);
    const publications = data.entries.filter(
      entry => entry.payload.operation === 'publish'
    );
    assert.equal(publications.length, 1);
    assert.equal(publications[0].payload.expected_version, null);
    assert.equal(
      publications[0].payload.session.user_id,
      baseEnv.INSTAGRAM_TESTER_ADMIN_USER_ID
    );
    assert.equal(data.headers.length, 1);
    assert.deepEqual(data.stderr, []);
  });
}

for (const operation of ['continue', 'abort']) {
  test(`persistent guard contains a rejected route.${operation} and still processes search then status`, async t => {
    const executions = [];
    const data = await syntheticManager(t, {
      vps: true,
      browserOperations: true,
      executeOperation: async ({ request }) => {
        executions.push(request.action);
        return {
          type: 'browser_operation',
          operation: 'complete',
          action: request.action,
          id: request.id,
          request_id: request.request_id,
          claim: request.claim,
          captured_at: '2026-10-08T12:00:00.000Z',
          ...(request.action === 'search'
            ? { results: [] }
            : {
                target_id: request.target_id,
                status: 'accepted',
              }),
        };
      },
    });
    const rejectedRoute = {
      request: () => ({
        url: () =>
          operation === 'continue'
            ? configuration(baseEnv).rolesUrl
            : 'https://unapproved.invalid/',
        method: () => 'GET',
        postData: () => null,
      }),
      continue: async () => {
        assert.equal(operation, 'continue');
        throw new Error('route.continue: Route is already handled!');
      },
      abort: async () => {
        throw new Error('route.abort: Route is already handled!');
      },
    };
    await assert.doesNotReject(data.route(rejectedRoute));
    await data.clock.advance(1000);
    data.browserRequest.action = 'status';
    data.browserRequest.target_id = '10004';
    await data.clock.advance(250);
    assert.deepEqual(executions, ['search', 'status']);
    assert.equal(data.closed(), 0);
    assert.ok(
      data.stderr.includes('{"event":"instagram_browser_route_failed"}\n')
    );
    let blocked = false;
    // Check an unapproved request separately from the handled route.
    await data.route({
      request: () => ({
        url: () => 'https://unapproved.invalid/',
        method: () => 'POST',
        postData: () => '',
      }),
      continue: async () => {
        assert.fail('unapproved request continued');
      },
      abort: async () => {
        blocked = true;
      },
    });
    assert.equal(blocked, true);
  });
}

for (const count of [1, 1000]) {
  test(`contains ${count} concurrent rejected browser routes without losing the next operation`, async t => {
    let executions = 0;
    const data = await syntheticManager(t, {
      vps: true,
      browserOperations: true,
      executeOperation: async ({ request }) => {
        executions += 1;
        return {
          type: 'browser_operation',
          operation: 'complete',
          action: request.action,
          id: request.id,
          request_id: request.request_id,
          claim: request.claim,
          captured_at: '2026-10-08T12:00:00.000Z',
          results: [],
        };
      },
    });
    await Promise.all(
      Array.from({ length: count }, (_, index) =>
        data.route({
          request: () => ({
            url: () =>
              index % 2
                ? 'https://unapproved.invalid/'
                : configuration(baseEnv).rolesUrl,
            method: () => 'GET',
            postData: () => null,
          }),
          continue: async () => {
            throw new Error('route.continue: Route is already handled!');
          },
          abort: async () => {
            throw new Error(
              'route.abort: Target page, context or browser has been closed'
            );
          },
        })
      )
    );
    await data.clock.advance(1000);
    assert.equal(executions, 1);
    assert.equal(data.closed(), 0);
    assert.equal(
      data.stderr.filter(
        value => value === '{"event":"instagram_browser_route_failed"}\n'
      ).length,
      count
    );
  });
}

test('route failure diagnostics cannot reject the browser callback', async () => {
  await assert.doesNotReject(
    handleBrowserRoute(
      {
        request: () => {
          throw new Error('synthetic_request_closed');
        },
        abort: async () => {
          throw new Error('synthetic_route_closed');
        },
      },
      configuration(baseEnv),
      {
        write: () => {
          throw new Error('synthetic_pipe_closed');
        },
      }
    )
  );
});

test('publishes the closed-page failure once, then releases the browser and profile before another read', async t => {
  let data;
  data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    executeOperation: async ({ request }) => {
      await data.page.close();
      return {
        type: 'browser_operation',
        operation: 'complete',
        action: request.action,
        id: request.id,
        request_id: request.request_id,
        claim: request.claim,
        captured_at: '2026-10-08T12:00:00.000Z',
        error_code: 'meta_unavailable',
      };
    },
  });
  await data.clock.advance(1000);
  const error = await data.settled;
  assert.equal(error?.message, 'browser_runtime_required');
  const completions = data.entries.filter(
    entry =>
      entry.payload.type === 'browser_operation' &&
      entry.payload.operation === 'complete'
  );
  assert.equal(completions.length, 1);
  assert.equal(completions[0].payload.error_code, 'meta_unavailable');
  const reads = data.entries.filter(
    entry =>
      entry.payload.type === 'browser_operation' &&
      entry.payload.operation === 'read'
  ).length;
  await data.clock.advance(2000);
  assert.equal(
    data.entries.filter(
      entry =>
        entry.payload.type === 'browser_operation' &&
        entry.payload.operation === 'read'
    ).length,
    reads
  );
  assert.equal(data.closed(), 1);
  await assert.rejects(lstat(data.lockPath), { code: 'ENOENT' });
});

test('does not expose a warm page or claim work before the publication CAS resolves', async t => {
  const warmStates = [];
  const data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    pendingPublish: true,
    browserRequestReadyAt: 0,
    executeOperation: async ({ request, warmMetaPage }) => {
      warmStates.push(warmMetaPage);
      return {
        type: 'browser_operation',
        operation: 'complete',
        action: request.action,
        id: request.id,
        request_id: request.request_id,
        claim: request.claim,
        captured_at: '2026-10-08T12:00:00.000Z',
        results: [],
      };
    },
  });
  assert.equal(
    data.entries.some(entry => entry.payload.operation === 'publish'),
    true
  );
  assert.equal(
    data.entries.some(entry => entry.payload.type === 'browser_operation'),
    false
  );
  assert.equal(warmStates.length, 0);
  data.pendingPublish.resolve(PUBLISHED_VERSION);
  await drain();
  assert.equal(warmStates.length, 1);
  assert.equal(warmStates[0].valid, true);
  data.signals.emit('SIGTERM');
  assert.equal(await data.settled, null);
  assert.equal(warmStates[0].formBody, null);
});

const INVITE_TARGET_ID = '178414000000000001';
const inviteBrowserRequest = Object.freeze({
  type: 'browser_operation',
  operation: 'request',
  id: '33333333-3333-4333-8333-333333333333',
  request_id: '44444444-4444-4444-8444-444444444444',
  claim: '55555555-5555-4555-8555-555555555555',
  action: 'invite',
  app_id: baseEnv.INSTAGRAM_META_DEVELOPER_APP_ID,
  username: 'synthetic.user',
  target_id: INVITE_TARGET_ID,
  deadline: '2999-01-01T00:00:00.000Z',
});

function browserCompletion(request, fields) {
  return {
    type: 'browser_operation',
    operation: 'complete',
    action: request.action,
    id: request.id,
    request_id: request.request_id,
    claim: request.claim,
    captured_at: '2026-10-08T12:00:00.000Z',
    ...fields,
  };
}

function browserOperationEntries(data, operation) {
  return data.entries.filter(
    entry =>
      entry.payload.type === 'browser_operation' &&
      entry.payload.operation === operation
  );
}

function lifecycleDiagnostics(data) {
  return data.stderr
    .filter(line => line.startsWith('{'))
    .map(line => JSON.parse(line))
    .filter(line => line.event === 'instagram_browser_operation_lifecycle');
}

test('passes a deadline that reserves the completion publish', async t => {
  const deadlines = [];
  const data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    browserRequestReadyAt: 0,
    browserPublishDelayMs: { read: 20000, claim: 20000 },
    executeOperation: async ({ request, deadlineAt }) => {
      deadlines.push(deadlineAt);
      return browserCompletion(request, { results: [] });
    },
  });
  await data.clock.advance(40000);
  await drain();
  const [read] = browserOperationEntries(data, 'read');
  const [claim] = browserOperationEntries(data, 'claim');
  assert.equal(read.at, 0);
  assert.equal(claim.at, 20000);
  assert.equal(deadlines.length, 1);
  assert.equal(Number.isFinite(deadlines[0]), true);
  assert.ok(deadlines[0] <= claim.at + 120000 - 35000);
  assert.ok(deadlines[0] <= read.at + 120000 - 35000);
  // 80 s of scope remain after the slow read and claim; 35 s stay reserved.
  assert.equal(deadlines[0], 40000 + 80000 - 35000);
  data.signals.emit('SIGTERM');
});

test('publishes a truthful completion when execution exhausts its budget, then restarts', async t => {
  const observed = {};
  const data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    browserRequestReadyAt: 0,
    browserRequest: inviteBrowserRequest,
    executeOperation: async ({ request, signal, deadlineAt }) => {
      observed.deadlineAt = deadlineAt;
      await new Promise(resolveAbort => {
        signal.addEventListener('abort', resolveAbort, { once: true });
      });
      observed.abortedAt = observed.clock.time;
      return browserCompletion(request, {
        target_id: request.target_id,
        error_code: 'invite_unknown',
        write_started: true,
      });
    },
  });
  observed.clock = data.clock;
  const [read] = browserOperationEntries(data, 'read');
  await data.clock.advance(120000);
  const error = await data.settled;
  const completions = browserOperationEntries(data, 'complete');
  assert.equal(completions.length, 1);
  assert.equal(completions[0].payload.error_code, 'invite_unknown');
  assert.equal(completions[0].payload.write_started, true);
  assert.ok(completions[0].at <= observed.deadlineAt + 1000);
  assert.ok(completions[0].at < read.at + 120000);
  assert.equal(
    lifecycleDiagnostics(data).some(line => line.complete_received === true),
    true
  );
  assert.equal(error?.message, 'browser_runtime_required');
});

test('permit publish honors timeoutMs and frees the channel', async t => {
  let data;
  const permit = {};
  data = await syntheticManager(t, {
    vps: true,
    browserOperations: true,
    // The first read is empty, so the executor runs after `data` is bound.
    browserRequestReadyAt: 250,
    browserRequest: inviteBrowserRequest,
    pendingPermit: true,
    executeOperation: async ({ request, permitInvite }) => {
      if (permit.started !== undefined)
        return browserCompletion(request, {
          target_id: request.target_id,
          error_code: 'meta_unavailable',
          write_started: false,
        });
      permit.started = data.clock.time;
      try {
        await permitInvite(
          {
            captured_at: '2026-10-08T12:00:00.000Z',
            target_id: request.target_id,
            username: request.username,
            status: 'absent',
          },
          { timeoutMs: 1000 }
        );
        permit.outcome = 'resolved';
      } catch {
        permit.outcome = 'rejected';
        permit.rejectedAfter = data.clock.time - permit.started;
      }
      return browserCompletion(request, {
        target_id: request.target_id,
        error_code: 'meta_unavailable',
        write_started: false,
      });
    },
  });
  await data.clock.advance(250);
  assert.equal(permit.started, 250);
  await data.clock.advance(1000);
  await drain();
  assert.equal(permit.outcome, 'rejected');
  assert.equal(permit.rejectedAfter, 1000);
  assert.equal(browserOperationEntries(data, 'invite_permit').length, 1);
  const completions = browserOperationEntries(data, 'complete');
  assert.equal(completions.length >= 1, true);
  assert.equal(completions[0].at, permit.started + 1000);
  assert.equal(completions[0].payload.error_code, 'meta_unavailable');
  assert.equal(
    lifecycleDiagnostics(data).some(line => line.complete_received === true),
    true
  );
  data.signals.emit('SIGTERM');
  assert.equal(await data.settled, null);
});
