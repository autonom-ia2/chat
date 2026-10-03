/* eslint-disable no-await-in-loop, no-restricted-syntax -- Synthetic lifecycle cases intentionally serialize process and filesystem operations. */
/* eslint-disable no-promise-executor-return -- The polling promise resolves from setTimeout without exposing its handle. */

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { configuration } from '../../scripts/instagram_testers/session-observer.mjs';
import { run } from '../../scripts/instagram_testers/session-manager.mjs';

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
  INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
  INSTAGRAM_META_BUSINESS_ID: '10002',
  INSTAGRAM_TESTER_ROLES_DOC_ID: '10003',
  INSTAGRAM_TESTER_ADMIN_USER_ID: '12345',
  INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
  INSTAGRAM_TESTER_PROXY_PORT: '9100',
  INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
};

const publisherProgram = [
  "let input = '';",
  "process.stdin.on('data', chunk => { input += chunk; });",
  "process.stdin.on('end', () => {",
  '  const request = JSON.parse(input);',
  "  const fs = require('node:fs');",
  "  fs.appendFileSync(process.env.SYNTHETIC_OPS_FILE, JSON.stringify(request) + '\\n');",
  `  const version = request.operation === 'version' ? '${INITIAL_VERSION}' : request.operation === 'publish' ? '${PUBLISHED_VERSION}' : null;`,
  '  process.stdout.write(JSON.stringify({ version }));',
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
}).toString();

class Request {
  url() { return 'https://developers.facebook.com/api/graphql/'; }
  method() { return 'POST'; }
  postData() { return fields; }
  async allHeaders() {
    return {
      cookie: 'c_user=' + process.env.INSTAGRAM_TESTER_ADMIN_USER_ID + '; xs=synthetic',
      'user-agent': 'Synthetic Browser',
      'x-fb-lsd': 'synthetic-lsd',
    };
  }
}

class Response {
  constructor(status) { this.responseStatus = status; }
  url() { return 'https://developers.facebook.com/api/graphql/'; }
  request() { return new Request(); }
  status() { return this.responseStatus; }
  async text() {
    if (mode === 'html') process.emit('SIGTERM');
    return mode === 'html' ? '<html>login</html>' : body;
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
    if (
      ![
        'redirect',
        'checkpoint-redirect',
        'status-401',
        'status-403',
      ].includes(mode)
    ) {
      this.emit('response', new Response(responseStatus));
    }
    return new Navigation(navigationStatus);
  }
}

class Context extends EventEmitter {
  constructor() { super(); this.page = new Page(); }
  pages() { return [this.page]; }
  async newPage() { return this.page; }
  async route() {}
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
  await writeFile(runtime, fakeRuntime, { mode: 0o600 });
  return {
    root,
    operations: operationLog,
    launch,
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
  throw new Error(
    `Synthetic operation not observed: ${operation}; observed=${JSON.stringify(await readOperations(path))}`
  );
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
      ['version', 'publish']
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

for (const status of [401, 403]) {
  test(`invalidates the stored version and stops on HTTP ${status}`, async () => {
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
        ['version', 'invalidate']
      );
      assert.equal(entries[1].expected_version, INITIAL_VERSION);
      assert.equal(entries[1].code, 'operator_required');
    } finally {
      process.emit('SIGTERM');
      await cleanup(data);
    }
  });
}

for (const status of [401, 403]) {
  test(`invalidates on GraphQL response HTTP ${status} with healthy navigation`, async () => {
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
        ['version', 'invalidate']
      );
      assert.equal(entries[1].expected_version, INITIAL_VERSION);
      assert.equal(entries[1].code, 'operator_required');
    } finally {
      process.emit('SIGTERM');
      await cleanup(data);
    }
  });
}

test('invalidates and stops on a login redirect without a direct HTTP fallback', async () => {
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
      ['version', 'invalidate']
    );
    assert.equal(entries[1].code, 'operator_required');
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

test('invalidates and stops on a checkpoint or two-factor redirect', async () => {
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
      ['version', 'invalidate']
    );
    assert.equal(entries[1].code, 'operator_required');
  } finally {
    process.emit('SIGTERM');
    await cleanup(data);
  }
});

test('rejects HTML/login response without invalidating the still-current version', async () => {
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
    assert.equal(error?.message, 'operator_required');
    assert.deepEqual(
      entries.map(entry => entry.operation),
      ['version']
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
