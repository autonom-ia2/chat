/*
 * Local-only latency harness for the existing browser-operation executor.
 * It launches an ephemeral Playwright browser, a synthetic HTTPS origin, and
 * a loopback CONNECT proxy. The browser still emits real Roles/typeahead/
 * invite requests, while the fixture transport never reaches Meta or AWS.
 * No production profile, credentials, cookies, or source files are used.
 */
/* eslint-disable no-await-in-loop, no-restricted-syntax, no-use-before-define, consistent-return -- The benchmark preserves ordered browser phases and event-handler return shapes. */

import assert from 'node:assert/strict';
import { createServer as createHttpsServer } from 'node:https';
import {
  connect as connectNet,
  createServer as createNetServer,
} from 'node:net';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { executeBrowserOperation } from '../../../scripts/instagram_testers/browser-operations.mjs';
import {
  handleBrowserRoute,
  isAllowedBrowserRequest,
} from '../../../scripts/instagram_testers/session-manager.mjs';
import { isMainModule } from '../../../scripts/instagram_testers/runtime/entrypoint.mjs';

const FIXTURE_PATH = new URL(
  './latency-browser-fixtures.json',
  import.meta.url
);
const ORIGIN = 'https://developers.facebook.com';
const GRAPHQL_PATH = '/api/graphql/';
const SEARCH_PATH = '/roles/instagram/typeahead/user/';
const ROLES_PAGE_PATH = '/apps/10001/roles/roles/';
const INVITE_PATH = '/apps/10001/async/instagram/roles/add/';
const MARK_NAMES = new Set([
  'operation_started',
  'operation_finished',
  'roles_navigation_started',
  'roles_navigation_completed',
  'roles_request',
  'roles_response',
  'add_people_clicked',
  'dialog_opened',
  'role_checked',
  'search_input_filled',
  'search_option_rendered',
  'search_target_selected',
  'invite_button_clicked',
  'typeahead_request',
  'typeahead_response',
  'invite_request',
  'invite_response',
]);
const UUIDS = Object.freeze({
  search: '11111111-1111-4111-8111-111111111111',
  status_accepted: '22222222-2222-4222-8222-222222222222',
  invite_unknown: '33333333-3333-4333-8333-333333333333',
});
const REQUEST_UUIDS = Object.freeze({
  search: '44444444-4444-4444-8444-444444444444',
  status_accepted: '55555555-5555-4555-8555-555555555555',
  invite_unknown: '66666666-6666-4666-8666-666666666666',
});
const CLAIM_UUIDS = Object.freeze({
  search: '77777777-7777-4777-8777-777777777777',
  status_accepted: '88888888-8888-4888-8888-888888888888',
  invite_unknown: '99999999-9999-4999-8999-999999999999',
});
let diagnosticStage = 'startup';

function fail(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

function normalizeConnectFault(value) {
  if (value === null) return null;
  if (!value || value.status !== 407 || typeof value.persistent !== 'boolean')
    fail('invalid_connect_fault');
  return { status: 407, persistent: value.persistent };
}

function monotonicClock() {
  const started = process.hrtime.bigint();
  const marks = Object.create(null);
  const now = () => Number(process.hrtime.bigint() - started) / 1e6;
  return {
    marks,
    mark(name) {
      if (MARK_NAMES.has(name) && marks[name] === undefined)
        marks[name] = now();
    },
    now,
  };
}

function between(marks, from, to) {
  if (!Number.isFinite(marks[from]) || !Number.isFinite(marks[to])) return null;
  const value = marks[to] - marks[from];
  return value >= 0 ? Number(value.toFixed(3)) : null;
}

function readArgs(argv) {
  const options = { iterations: 1, output: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--iterations') {
      index += 1;
      const value = Number(argv[index]);
      if (!Number.isInteger(value) || value < 1 || value > 20)
        fail('invalid_iterations');
      options.iterations = value;
    } else if (argument === '--output') {
      index += 1;
      options.output = argv[index];
      if (!options.output || options.output.includes('\0'))
        fail('invalid_output');
    } else if (argument === '--help') {
      options.help = true;
    } else {
      fail('unknown_argument');
    }
  }
  return options;
}

function safeClass(error) {
  const value = error?.name || error?.constructor?.name || 'Error';
  return /^[A-Za-z][A-Za-z0-9_:]{0,95}$/.test(value) ? value : 'Error';
}

function safeCode(error) {
  const value = error?.code;
  return typeof value === 'string' && /^[a-z][a-z0-9_]{0,95}$/.test(value)
    ? value
    : null;
}

function setDiagnosticStage(stage) {
  if (/^[a-z][a-z0-9_]{0,63}$/.test(stage)) diagnosticStage = stage;
}

function namedScenarios(fixture) {
  const scenarios = fixture?.scenarios;
  if (!scenarios || typeof scenarios !== 'object' || Array.isArray(scenarios))
    fail('invalid_named_scenarios');
  const names = Object.keys(scenarios);
  const requiredNames = new Set([
    'search',
    'status_accepted',
    'invite_unknown',
  ]);
  if (
    names.length !== requiredNames.size ||
    names.some(name => !requiredNames.has(name))
  )
    fail('invalid_named_scenarios');
  for (const name of names) {
    const definition = scenarios[name];
    if (
      !definition ||
      typeof definition !== 'object' ||
      !['search', 'status', 'invite'].includes(definition.action) ||
      !['result', 'target'].includes(definition.target) ||
      !['ABSENT', 'CONFIRMED'].includes(definition.roles_target_status) ||
      !['none', 'target'].includes(definition.typeahead_entries)
    )
      fail('invalid_named_scenario_definition');
  }
  if (
    scenarios.search.action !== 'search' ||
    scenarios.search.target !== 'result' ||
    scenarios.status_accepted.action !== 'status' ||
    scenarios.status_accepted.target !== 'target' ||
    scenarios.invite_unknown.action !== 'invite' ||
    scenarios.invite_unknown.target !== 'target'
  )
    fail('invalid_named_scenario_binding');
  return Object.freeze(names);
}

export async function loadChromium() {
  const modulePath = process.env.PLAYWRIGHT_MODULE_PATH;
  if (!modulePath || modulePath.includes('\0'))
    fail('playwright_module_missing');
  const imported = await import(pathToFileURL(modulePath).href);
  const chromium = imported.chromium || imported.default?.chromium;
  if (!chromium || typeof chromium.launch !== 'function')
    fail('playwright_module_invalid');
  return chromium;
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    const value = Buffer.from(chunk);
    size += value.length;
    if (size > 262144) fail('fixture_body_too_large');
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function jsonResponse(body, status = 200) {
  return { status, body: JSON.stringify(body) };
}

function htmlResponse(body, status = 200) {
  return { status, body, contentType: 'text/html; charset=utf-8' };
}

function rolesDocument(scenario, fixture) {
  const definition = fixture.scenarios[scenario];
  if (!definition) fail('invalid_fixture_scenario');
  const user = {
    id: fixture.target.id,
    status: definition.roles_target_status,
  };
  const users = definition.roles_target_status === 'CONFIRMED' ? [user] : [];
  return {
    data: {
      get_app_roles: {
        app_roles: [
          { role: 'instagram testers', users },
          { role: 'developers', users: [] },
        ],
      },
    },
  };
}

function typeaheadDocument(fixture) {
  return {
    payload: {
      entries: [
        {
          uniqueID: fixture.target.id,
          text: fixture.target.username,
          subtitle: fixture.target.name,
          photo: null,
        },
      ],
    },
  };
}

function fixtureResponse(scenario, fixture, url, method) {
  if (method === 'OPTIONS') return jsonResponse({}, 204);
  if (
    method === 'GET' &&
    url.pathname === ROLES_PAGE_PATH &&
    url.searchParams.get('business_id') === '10002'
  )
    return htmlResponse(createFixtureHtml(fixture, scenario));
  if (method !== 'POST')
    return jsonResponse({ error: 'fixture_method_rejected' }, 405);
  if (url.pathname === GRAPHQL_PATH)
    return jsonResponse(rolesDocument(scenario, fixture));
  if (url.pathname === SEARCH_PATH) {
    if (fixture.scenarios[scenario]?.typeahead_entries !== 'target')
      return jsonResponse({ payload: { entries: [] } });
    return jsonResponse(typeaheadDocument(fixture));
  }
  if (url.pathname === INVITE_PATH) return jsonResponse({ payload: {} });
  return jsonResponse({ error: 'fixture_path_rejected' }, 404);
}

async function listen(server) {
  await new Promise((resolvePromise, reject) => {
    const onError = error => {
      server.off('listening', resolvePromise);
      reject(error);
    };
    server.once('error', onError);
    server.once('listening', resolvePromise);
    server.listen(0, '127.0.0.1');
  });
  const address = server.address();
  if (!address || typeof address === 'string') fail('fixture_listener_invalid');
  return address.port;
}

function closeServer(server) {
  if (!server) return Promise.resolve();
  return new Promise(resolvePromise => {
    server.close(() => resolvePromise());
    server.closeAllConnections?.();
  });
}

export function createFixtureHtml(fixture, scenario) {
  const target = JSON.stringify(fixture.target);
  const searchUrl = JSON.stringify(`${ORIGIN}${SEARCH_PATH}`);
  const inviteUrl = JSON.stringify(`${ORIGIN}${INVITE_PATH}`);
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>synthetic browser latency fixture</title></head>
<body>
  <main>
    <button type="button" id="add-people">Add people</button>
    <section id="tester-dialog" role="dialog" hidden>
      <fieldset>
        <legend>Role</legend>
        <label><input type="radio" name="role" id="instagram-testers-role">Instagram testers</label>
      </fieldset>
      <input id="tester-search" type="text" role="combobox" aria-controls="latency-listbox" autocomplete="off">
      <div id="latency-listbox" role="listbox" hidden></div>
      <button type="button" id="invite">Add</button>
    </section>
  </main>
<script>
  const scenario = ${JSON.stringify(scenario)};
  const target = ${target};
  const searchUrl = ${searchUrl};
  const inviteUrl = ${inviteUrl};
  const mark = name => window.__latencyMark?.(name);
  const roleFields = () => new URLSearchParams([
    ['fb_api_req_friendly_name', 'RolesTable_Query'],
    ['doc_id', '10003'],
    ['__bid', '10002'],
    ['__user', '12345'],
    ['av', '12345'],
    ['variables', '{"app_id":"10001"}'],
    ['__aaid', '9000001'],
  ]);
  const typeaheadFields = () => new URLSearchParams([
    ['__aaid', '9000001'], ['__bid', '10002'], ['__user', '12345'],
    ['__a', '1'], ['__req', '1'], ['__hs', '1'], ['dpr', '1'],
    ['__ccg', '1'], ['__rev', '1'], ['__s', ''], ['__hsi', '1'],
    ['__dyn', '1'], ['fb_dtsg', 'synthetic_fb_dtsg'],
    ['jazoest', 'synthetic_jazoest'], ['lsd', 'synthetic_lsd'],
    ['qpl_active_flow_ids', ''],
  ]);
  const inviteFields = () => {
    const fields = typeaheadFields();
    fields.set('role', 'instagram testers');
    fields.set('user_id_or_vanitys[0]', target.id);
    fields.set('reload_on_success', 'false');
    return fields;
  };
  const addPeople = document.getElementById('add-people');
  const dialog = document.getElementById('tester-dialog');
  const role = document.getElementById('instagram-testers-role');
  const input = document.getElementById('tester-search');
  const listbox = document.getElementById('latency-listbox');
  const invite = document.getElementById('invite');
  addPeople.addEventListener('click', () => {
    mark('add_people_clicked');
    dialog.hidden = false;
    mark('dialog_opened');
  });
  role.addEventListener('change', () => mark('role_checked'));
  input.addEventListener('input', async () => {
    mark('search_input_filled');
    if (!listbox.querySelector('[role="option"]')) {
      listbox.hidden = false;
      const option = document.createElement('div');
      option.setAttribute('role', 'option');
      option.textContent = target.username;
      option.setAttribute('aria-label', target.username);
      option.addEventListener('click', () => {
        option.remove();
        listbox.hidden = true;
        const selected = document.createElement('button');
        selected.type = 'button';
        selected.setAttribute('role', 'button');
        selected.textContent = target.username;
        selected.setAttribute('aria-label', target.username);
        dialog.insertBefore(selected, invite);
        mark('search_target_selected');
      });
      listbox.append(option);
      mark('search_option_rendered');
    }
    await fetch(searchUrl + '?value=' + encodeURIComponent(input.value), {
      method: 'POST', body: typeaheadFields(),
    });
  });
  invite.addEventListener('click', async () => {
    mark('invite_button_clicked');
    await fetch(inviteUrl, { method: 'POST', body: inviteFields() });
  });
  fetch(${JSON.stringify(`${ORIGIN}${GRAPHQL_PATH}`)}, {
    method: 'POST', body: roleFields(),
  }).catch(() => {});
</script></body></html>`;
}

export async function createFixtureTransport(fixture, scenarioNames) {
  const certDirectory = await mkdtemp(
    join(tmpdir(), 'instagram-latency-cert-')
  );
  const keyPath = join(certDirectory, 'key.pem');
  const certPath = join(certDirectory, 'cert.pem');
  const openssl = spawnSync(
    'openssl',
    [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=developers.facebook.com',
      '-addext',
      'subjectAltName=DNS:developers.facebook.com',
      '-keyout',
      keyPath,
      '-out',
      certPath,
    ],
    { stdio: 'ignore', timeout: 15000 }
  );
  if (openssl.error || openssl.status !== 0)
    fail('openssl_fixture_unavailable');
  const key = await readFile(keyPath);
  const cert = await readFile(certPath);
  let activeScenario = null;
  let responseFault = null;
  let responseFaultHits = 0;
  let connectFault = null;
  let connectFaultHits = 0;
  const requestCounts = { roles: 0, typeahead: 0, invite: 0 };
  const httpsServer = createHttpsServer(
    { key, cert },
    async (request, response) => {
      try {
        const url = new URL(request.url || '/', ORIGIN);
        await readBody(request);
        let result = fixtureResponse(
          activeScenario,
          fixture,
          url,
          request.method
        );
        if (url.pathname === GRAPHQL_PATH) requestCounts.roles += 1;
        if (url.pathname === SEARCH_PATH) requestCounts.typeahead += 1;
        if (url.pathname === INVITE_PATH) requestCounts.invite += 1;
        if (responseFault?.path === url.pathname) {
          const selected = responseFault;
          if (!selected.persistent) responseFault = null;
          responseFaultHits += 1;
          selected.onHit?.();
          if (selected.disconnect) {
            response.destroy();
            return;
          }
          if (selected.delayMs) await delay(selected.delayMs);
          result = { ...result, ...selected };
        }
        response.writeHead(result.status, {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'content-type',
          'access-control-allow-methods': 'POST, OPTIONS',
          'content-type': result.contentType || 'application/json',
          'content-length': Buffer.byteLength(result.body),
        });
        response.end(result.body);
      } catch {
        response.writeHead(500, {
          'access-control-allow-origin': '*',
          'content-type': 'application/json',
        });
        response.end('{"error":"fixture_failed"}');
      }
    }
  );
  httpsServer.keepAliveTimeout = 1000;
  const fixturePort = await listen(httpsServer);
  const proxyServer = createNetServer(socket => {
    let header = Buffer.alloc(0);
    let connected = false;
    const reject = () => {
      socket.destroy();
    };
    const onData = chunk => {
      if (connected) return;
      header = Buffer.concat([header, Buffer.from(chunk)]);
      if (header.length > 16384) return reject();
      const end = header.indexOf('\r\n\r\n');
      if (end < 0) return;
      const firstLine = header
        .subarray(0, end)
        .toString('latin1')
        .split('\r\n')[0];
      const [method, target] = firstLine.split(' ');
      if (method !== 'CONNECT' || target !== 'developers.facebook.com:443')
        return reject();
      if (connectFault) {
        const selected = connectFault;
        connectFaultHits += 1;
        if (!selected.persistent) connectFault = null;
        socket.end(
          `HTTP/1.1 ${selected.status} Proxy Authentication Required\r\n` +
            'Proxy-Authenticate: Basic realm="synthetic"\r\n' +
            'Connection: close\r\n' +
            'Content-Length: 0\r\n\r\n'
        );
        return;
      }
      connected = true;
      socket.off('data', onData);
      const upstream = connectNet({ host: '127.0.0.1', port: fixturePort });
      upstream.once('connect', () => {
        socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        const remainder = header.subarray(end + 4);
        if (remainder.length) upstream.write(remainder);
        socket.pipe(upstream);
        upstream.pipe(socket);
      });
      upstream.on('error', reject);
      socket.on('error', () => upstream.destroy());
    };
    socket.on('data', onData);
    socket.on('error', () => {});
    socket.setTimeout(30000, reject);
  });
  const proxyPort = await listen(proxyServer);
  const proxy = `http://127.0.0.1:${proxyPort}`;
  return {
    proxy,
    setScenario(value) {
      if (!scenarioNames.includes(value)) fail('invalid_fixture_scenario');
      activeScenario = value;
    },
    setResponseFault(value) {
      responseFault = value;
    },
    responseFaultHits() {
      return responseFaultHits;
    },
    pendingResponseFault() {
      return responseFault !== null;
    },
    setConnectFault(value) {
      connectFault = normalizeConnectFault(value);
    },
    connectFaultHits() {
      return connectFaultHits;
    },
    pendingConnectFault() {
      return connectFault !== null;
    },
    async probeConnectChallenge() {
      const endpoint = new URL(proxy);
      return new Promise(resolvePromise => {
        const socket = connectNet({
          host: endpoint.hostname,
          port: Number(endpoint.port),
        });
        let header = Buffer.alloc(0);
        let settled = false;
        const finish = result => {
          if (settled) return;
          settled = true;
          socket.destroy();
          resolvePromise(result);
        };
        socket.setTimeout(3000, () =>
          finish({ status: null, event: 'timeout' })
        );
        socket.on('connect', () =>
          socket.write(
            'CONNECT developers.facebook.com:443 HTTP/1.1\r\n' +
              'Host: developers.facebook.com:443\r\n\r\n'
          )
        );
        socket.on('data', chunk => {
          header = Buffer.concat([header, Buffer.from(chunk)]);
          if (header.length > 16384) {
            finish({ status: null, event: 'oversize' });
            return;
          }
          const end = header.indexOf('\r\n\r\n');
          if (end < 0) return;
          const firstLine = header
            .subarray(0, end)
            .toString('latin1')
            .split('\r\n')[0];
          const statusMatch = /^HTTP\/1\.[01] ([0-9]{3})(?: |$)/.exec(
            firstLine
          );
          finish({
            status: statusMatch ? Number(statusMatch[1]) : null,
            event: statusMatch ? 'headers' : 'invalid_headers',
          });
        });
        socket.on('error', () => finish({ status: null, event: 'error' }));
        socket.on('close', () => finish({ status: null, event: 'closed' }));
      });
    },
    counts() {
      return { ...requestCounts };
    },
    async close() {
      await Promise.all([closeServer(proxyServer), closeServer(httpsServer)]);
      await rm(certDirectory, { recursive: true, force: true });
    },
  };
}

export function makeConfiguration(fixture) {
  return {
    appId: fixture.configuration.app_id,
    businessId: fixture.configuration.business_id,
    docId: fixture.configuration.roles_doc_id,
    adminId: fixture.configuration.admin_id,
    rolesUrl: `${ORIGIN}${fixture.configuration.roles_path}`,
  };
}

export function makeRequest(scenario, configuration, fixture, iteration) {
  const definition = fixture.scenarios[scenario];
  if (!definition) fail('invalid_fixture_scenario');
  const request = {
    action: definition.action,
    app_id: configuration.appId,
    id: UUIDS[scenario],
    request_id: REQUEST_UUIDS[scenario],
    claim: CLAIM_UUIDS[scenario],
    username: fixture.target.username,
  };
  if (definition.target === 'target') request.target_id = fixture.target.id;
  if (iteration > 1) {
    const suffix = String(iteration).padStart(2, '0');
    request.id = `${UUIDS[scenario].slice(0, -2)}${suffix}`;
    request.request_id = `${REQUEST_UUIDS[scenario].slice(0, -2)}${suffix}`;
    request.claim = `${CLAIM_UUIDS[scenario].slice(0, -2)}${suffix}`;
  }
  return request;
}

function requestPath(value) {
  try {
    return new URL(value).pathname;
  } catch {
    return null;
  }
}

function buildPhaseMetrics(clock, requestCounts) {
  const marks = clock.marks;
  return {
    total_ms: between(marks, 'operation_started', 'operation_finished'),
    roles_navigation_ms: between(
      marks,
      'roles_navigation_started',
      'roles_navigation_completed'
    ),
    roles_http_ms: between(marks, 'roles_request', 'roles_response'),
    add_people_to_dialog_ms: between(
      marks,
      'add_people_clicked',
      'dialog_opened'
    ),
    dialog_to_role_checked_ms: between(marks, 'dialog_opened', 'role_checked'),
    role_to_input_ms: between(marks, 'role_checked', 'search_input_filled'),
    typeahead_http_ms: between(
      marks,
      'typeahead_request',
      'typeahead_response'
    ),
    typeahead_to_option_ms: between(
      marks,
      'typeahead_response',
      'search_option_rendered'
    ),
    option_to_selected_ms: between(
      marks,
      'search_option_rendered',
      'search_target_selected'
    ),
    selected_to_invite_click_ms: between(
      marks,
      'search_target_selected',
      'invite_button_clicked'
    ),
    invite_http_ms: between(marks, 'invite_request', 'invite_response'),
    request_counts: requestCounts,
  };
}

function sanitizeOutcome(action, result) {
  if (action === 'search') {
    return {
      ok: Array.isArray(result?.results),
      candidate_count: Array.isArray(result?.results)
        ? result.results.length
        : 0,
      error_code: result?.error_code || null,
    };
  }
  if (action === 'status') {
    return {
      ok: result?.status === 'accepted',
      status: result?.status || null,
      error_code: result?.error_code || null,
    };
  }
  return {
    ok: result?.error_code === 'invite_unknown',
    error_code: result?.error_code || null,
    write_started: result?.write_started === true,
  };
}

function summarizeSamples(samples) {
  const values = samples
    .map(sample => sample.phase_ms.total_ms)
    .filter(value => Number.isFinite(value))
    .sort((left, right) => left - right);
  const percentile = fraction => {
    if (!values.length) return null;
    return values[
      Math.min(values.length - 1, Math.ceil(values.length * fraction) - 1)
    ];
  };
  return {
    sample_count: samples.length,
    successful_samples: samples.filter(sample => sample.outcome.ok).length,
    total_ms: {
      min: values[0] ?? null,
      median: percentile(0.5),
      p95: percentile(0.95),
      max: values.at(-1) ?? null,
    },
  };
}

async function runBenchmark(options, fixture, scenarioNames) {
  const configuration = makeConfiguration(fixture);
  setDiagnosticStage('playwright_load');
  const chromium = await loadChromium();
  const executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
  if (!executablePath || executablePath.includes('\0'))
    fail('playwright_executable_missing');
  setDiagnosticStage('fixture_transport');
  const transport = await createFixtureTransport(fixture, scenarioNames);
  let browser;
  let context;
  let activeClock = null;
  const samples = [];
  try {
    setDiagnosticStage('browser_launch');
    browser = await chromium.launch({
      headless: true,
      ignoreHTTPSErrors: true,
      executablePath,
      proxy: { server: transport.proxy },
      args: [
        '--disable-background-networking',
        '--disable-component-update',
        '--disable-default-apps',
        '--disable-sync',
      ],
    });
    setDiagnosticStage('context_create');
    context = await browser.newContext({ ignoreHTTPSErrors: true });
    await context.route('**/*', route =>
      handleBrowserRoute(route, configuration, process.stderr)
    );
    setDiagnosticStage('page_create');
    const rawPage = await context.newPage();
    setDiagnosticStage('page_observers');
    await rawPage.exposeFunction('__latencyMark', name => {
      if (typeof name === 'string' && MARK_NAMES.has(name))
        activeClock?.mark(name);
    });
    const page = rawPage;
    const requestCounts = { roles: 0, typeahead: 0, invite: 0 };
    rawPage.on('request', request => {
      const path = requestPath(request.url());
      if (path === ROLES_PAGE_PATH) {
        activeClock?.mark('roles_navigation_started');
      } else if (path === GRAPHQL_PATH) {
        requestCounts.roles += 1;
        activeClock?.mark('roles_request');
      } else if (path === SEARCH_PATH) {
        requestCounts.typeahead += 1;
        activeClock?.mark('typeahead_request');
      } else if (path === INVITE_PATH) {
        requestCounts.invite += 1;
        activeClock?.mark('invite_request');
      }
    });
    rawPage.on('domcontentloaded', () => {
      activeClock?.mark('roles_navigation_completed');
    });
    rawPage.on('response', response => {
      const path = requestPath(response.url());
      if (path === GRAPHQL_PATH) activeClock?.mark('roles_response');
      else if (path === SEARCH_PATH) activeClock?.mark('typeahead_response');
      else if (path === INVITE_PATH) activeClock?.mark('invite_response');
    });
    for (let iteration = 1; iteration <= options.iterations; iteration += 1) {
      for (const scenario of scenarioNames) {
        setDiagnosticStage(`operation_${scenario}`);
        transport.setScenario(scenario);
        activeClock = monotonicClock();
        activeClock.mark('operation_started');
        const request = makeRequest(
          scenario,
          configuration,
          fixture,
          iteration
        );
        const result = await executeBrowserOperation({
          page,
          configuration,
          request,
          signal: AbortSignal.timeout(120000),
          requestGuard: parameters =>
            isAllowedBrowserRequest({ ...parameters, config: configuration }),
          permitInvite:
            scenario === 'invite_unknown'
              ? permitRequest => ({
                  type: 'browser_operation',
                  operation: 'invite_permit',
                  id: permitRequest.id,
                  request_id: permitRequest.request_id,
                  claim: permitRequest.claim,
                  decision: 'write',
                  status: 'absent',
                })
              : undefined,
          now: Date.now,
        });
        activeClock.mark('operation_finished');
        const phaseMs = buildPhaseMetrics(activeClock, { ...requestCounts });
        samples.push({
          scenario,
          iteration,
          page_reused: true,
          context_reused: true,
          outcome: sanitizeOutcome(fixture.scenarios[scenario].action, result),
          phase_ms: phaseMs,
          monotonic_marks_ms: { ...activeClock.marks },
        });
        requestCounts.roles = 0;
        requestCounts.typeahead = 0;
        requestCounts.invite = 0;
        activeClock = null;
      }
    }
    setDiagnosticStage('benchmark_complete');
  } finally {
    activeClock = null;
    await context?.close().catch(() => {});
    await browser?.close().catch(() => {});
    await transport.close();
  }
  return samples;
}

function printHelp() {
  process.stdout.write(
    'usage: node .codex/latency-browser-benchmark.mjs [--iterations N] [--output PATH]\n'
  );
}

async function main(argv = process.argv.slice(2)) {
  const options = readArgs(argv);
  if (options.help) {
    printHelp();
    return;
  }
  const fixture = JSON.parse(await readFile(FIXTURE_PATH, 'utf8'));
  assert.equal(fixture.production_mutated, false);
  assert.equal(fixture.meta_called, false);
  const scenarioNames = namedScenarios(fixture);
  const samples = await runBenchmark(options, fixture, scenarioNames);
  const report = {
    status: samples.every(sample => sample.outcome.ok) ? 'passed' : 'failed',
    benchmark: 'browser_operation_local_synthetic',
    production_mutated: false,
    meta_called: false,
    browser_headless: true,
    page_reused: true,
    context_reused: true,
    monotonic_clock: 'process.hrtime.bigint',
    iterations: options.iterations,
    scenarios: scenarioNames,
    scenario_contract: Object.fromEntries(
      scenarioNames.map(name => [
        name,
        {
          action: fixture.scenarios[name].action,
          target: fixture.scenarios[name].target,
        },
      ])
    ),
    samples,
    summaries: Object.fromEntries(
      scenarioNames.map(scenario => [
        scenario,
        summarizeSamples(
          samples.filter(sample => sample.scenario === scenario)
        ),
      ])
    ),
    provided_reference_series_seconds:
      fixture.provided_reference_series_seconds,
    provided_ten_x_targets_seconds: fixture.provided_ten_x_targets_seconds,
    reference_mapping: fixture.reference_mapping,
    limits: [
      'Synthetic local HTTPS/proxy transport; no Meta or AWS latency.',
      'Reference series is retained in supplied order because the receipt did not provide semantic labels.',
      'UI fixture renders the target option before the synthetic typeahead response to keep the local run deterministic; HTTP and executor phases remain real.',
    ],
  };
  if (options.output)
    await writeFile(options.output, `${JSON.stringify(report, null, 2)}\n`, {
      mode: 0o600,
    });
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

if (isMainModule(import.meta.url))
  main().catch(error => {
    process.stdout.write(
      `${JSON.stringify({
        status: 'error',
        error_class: safeClass(error),
        error_code: safeCode(error),
        diagnostic_stage: diagnosticStage,
        production_mutated: false,
        meta_called: false,
      })}\n`
    );
    process.exitCode = 1;
  });
