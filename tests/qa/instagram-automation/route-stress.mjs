/* eslint-disable no-await-in-loop, no-restricted-syntax -- Stress cases intentionally serialize browser faults and recovery. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { executeBrowserOperation } from '../../../scripts/instagram_testers/browser-operations.mjs';
import {
  handleBrowserRoute,
  isAllowedBrowserRequest,
} from '../../../scripts/instagram_testers/session-manager.mjs';
import {
  createFixtureTransport,
  loadChromium,
  makeConfiguration,
  makeRequest,
} from './latency-benchmark.mjs';

const printReport = serialized => process.stdout.write(serialized + '\n');

const fixture = JSON.parse(
  await readFile(
    new URL('./latency-browser-fixtures.json', import.meta.url),
    'utf8'
  )
);
assert.equal(fixture.meta_called, false);
assert.equal(fixture.production_mutated, false);
const config = makeConfiguration(fixture);
const transport = await createFixtureTransport(
  fixture,
  Object.keys(fixture.scenarios)
);
const chromium = await loadChromium();
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH,
  proxy: { server: transport.proxy },
  args: [
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
  ],
});
let context = await browser.newContext({ ignoreHTTPSErrors: true });
const diagnostics = [];
const errors = [];
const cases = [];
const phases = [];
const requestFailures = [];
const responseStatuses = [];
const responseOnly = process.env.INSTAGRAM_STRESS_HTTP_ONLY === '1';
let fault = null;
let sequence = 1;
let page = await context.newPage();
const onUnhandled = () => errors.push('unhandled_rejection');
process.on('unhandledRejection', onUnhandled);
await page.exposeFunction('__latencyMark', () => {});

const realGoto = page.goto.bind(page);
page.goto = async (...args) => {
  try {
    return await realGoto(...args);
  } catch (error) {
    const message = error.message || '';
    printReport(
      JSON.stringify({
        event: 'fixture_navigation_failed',
        closed: page.isClosed(),
        failed: message.includes('ERR_FAILED'),
        aborted: message.includes('ERR_ABORTED'),
        interrupted: message.includes('interrupted by another navigation'),
        detached: message.includes('detached'),
        timeout: message.includes('Timeout'),
        target_closed: message.includes('has been closed'),
        location_is_roles: page.url() === config.rolesUrl,
      })
    );
    throw error;
  }
};

const browserGuard = async route => {
  const selected = fault;
  if (
    selected &&
    ((route.request().isNavigationRequest() &&
      selected !== 'already_handled_background') ||
      (!route.request().isNavigationRequest() &&
        route.request().url() === config.rolesUrl &&
        selected === 'already_handled_background'))
  ) {
    fault = null;
    if (['already_handled', 'already_handled_background'].includes(selected))
      await route.abort();
    if (selected === 'delayed') await delay(100);
    if (selected === 'timeout') await delay(150);
    if (selected === 'network_failure') {
      await route.abort('failed');
      return;
    }
    if (selected === 'page_closed')
      await route.request().frame().page().close();
  }
  await handleBrowserRoute(route, config, {
    write: marker => diagnostics.push(marker),
  });
};
await context.route('**/*', browserGuard);

async function operation(scenario, signal, timeout = 5000) {
  // Match the production manager's polling interval between independent requests.
  await delay(1000);
  transport.setScenario(scenario);
  const request = makeRequest(scenario, config, fixture, sequence);
  sequence += 1;
  const failed = failedRequest => {
    const code =
      failedRequest.failure()?.errorText?.match(/net::ERR_[A-Z_]+/)?.[0] ||
      'unclassified';
    requestFailures.push(code);
  };
  const responded = response => responseStatuses.push(response.status());
  page.on('requestfailed', failed);
  page.on('response', responded);
  try {
    return await executeBrowserOperation({
      page,
      configuration: config,
      request,
      signal: signal || AbortSignal.timeout(timeout),
      onDiagnostic: value => phases.push(value),
      requestGuard: parameters =>
        isAllowedBrowserRequest({ ...parameters, config }),
      permitInvite:
        scenario === 'invite_unknown'
          ? observation => ({
              type: 'browser_operation',
              operation: 'invite_permit',
              id: observation.id,
              request_id: observation.request_id,
              claim: observation.claim,
              decision: 'write',
              status: 'absent',
            })
          : undefined,
    });
  } finally {
    page.off('requestfailed', failed);
    page.off('response', responded);
  }
}

async function accepted() {
  const result = await operation('status_accepted');
  if (result.status !== 'accepted')
    printReport(
      JSON.stringify({
        status: 'failed',
        operation: 'status',
        error_code: result.error_code,
        phases: phases.slice(-3),
        completed_cases: cases,
      })
    );
  assert.equal(result.status, 'accepted');
  assert.equal(result.error_code, undefined);
}

try {
  if (!responseOnly) {
    for (let iteration = 0; iteration < 10; iteration += 1) {
      const search = await operation('search');
      assert.equal(search.results?.length, 1);
      await accepted();
      const inviteCount = transport.counts().invite;
      const uncertain = await operation('invite_unknown');
      if (uncertain.error_code !== 'invite_unknown')
        printReport(
          JSON.stringify({
            status: 'case_failed',
            name: 'uncertain_invite',
            iteration,
            actual: uncertain.error_code || null,
            result_status: uncertain.status || null,
            write_started: uncertain.write_started,
            phases: phases.slice(-3),
            completed_cases: cases,
          })
        );
      assert.equal(uncertain.error_code, 'invite_unknown');
      assert.equal(uncertain.write_started, true);
      assert.equal(transport.counts().invite - inviteCount, 1);
      cases.push({
        name: 'search_status_uncertain_invite',
        iteration,
        passed: true,
      });
    }

    for (let iteration = 0; iteration < 10; iteration += 1) {
      fault = 'already_handled_background';
      await page.evaluate(async url => {
        try {
          await fetch(url);
        } catch {
          /* Deliberately aborted synthetic request. */
        }
      }, config.rolesUrl);
      await accepted();
      cases.push({
        name: 'real_background_route_already_handled_then_status',
        iteration,
        passed: true,
      });
    }

    fault = 'already_handled';
    await assert.rejects(page.goto(config.rolesUrl, { timeout: 5000 }));
    const interrupted = await operation('status_accepted');
    assert.ok(
      interrupted.status === 'accepted' ||
        interrupted.error_code === 'meta_unavailable'
    );
    // The production manager already polls at one second between requests.
    // This is a new explicit fixture request, not an automatic product retry.
    await delay(1000);
    await accepted();
    cases.push({
      name: 'cancelled_navigation_returns_typed_result_then_manager_poll_recovery',
      immediate_error: interrupted.error_code || null,
      passed: true,
    });
    assert.ok(
      diagnostics.includes('{"event":"instagram_browser_route_failed"}\n')
    );

    transport.setResponseFault({ path: '/api/graphql/', delayMs: 100 });
    await accepted();
    cases.push({ name: 'delayed_route', passed: true });

    const cancelledController = new AbortController();
    transport.setResponseFault({
      path: '/apps/10001/roles/roles/',
      delayMs: 150,
      onHit: () =>
        setTimeout(
          () => cancelledController.abort(new Error('operation_timeout')),
          25
        ),
    });
    const cancelled = await operation(
      'status_accepted',
      cancelledController.signal,
      5000
    );
    assert.equal(transport.pendingResponseFault(), false);
    assert.ok(cancelled.error_code);
    // The manager's existing executionPending path closes this lifecycle on timeout.
    // Reusing the interrupted page here would test a path the manager does not take.
    await context.close();
    context = await browser.newContext({ ignoreHTTPSErrors: true });
    await context.route('**/*', browserGuard);
    page = await context.newPage();
    await page.exposeFunction('__latencyMark', () => {});
    await accepted();
    cases.push({ name: 'timeout_then_new_lifecycle_fixture', passed: true });

    const networkHits = transport.responseFaultHits();
    transport.setResponseFault({
      path: '/apps/10001/roles/roles/',
      persistent: true,
      disconnect: true,
    });
    const network = await operation('status_accepted');
    assert.equal(network.error_code, 'meta_unavailable');
    assert.ok(transport.responseFaultHits() > networkHits);
    transport.setResponseFault(null);
    await delay(1000);
    await accepted();
    cases.push({ name: 'network_failure_then_status', passed: true });

    page.once('request', () => {
      page.close().catch(() => {});
    });
    const closed = await operation('status_accepted');
    assert.equal(closed.error_code, 'meta_unavailable');
    page = await context.newPage();
    await page.exposeFunction('__latencyMark', () => {});
    await accepted();
    cases.push({ name: 'closed_page_replacement_in_fixture', passed: true });

    await assert.rejects(
      page.goto('https://unapproved.invalid/', { timeout: 5000 })
    );
    // Allow the manager's existing polling interval after failed document navigation.
    await delay(1000);
    await accepted();
    cases.push({ name: 'unapproved_origin_blocked_then_status', passed: true });
  }

  const acceptedDocument = {
    data: {
      get_app_roles: {
        app_roles: [
          {
            role: 'instagram testers',
            users: [{ id: fixture.target.id, status: 'CONFIRMED' }],
          },
        ],
      },
    },
  };
  const responseCases = [
    {
      name: 'navigation_401',
      path: '/apps/10001/roles/roles/',
      status: 401,
      body: '<html></html>',
      expected: 'meta_session_expired',
    },
    {
      name: 'navigation_403',
      path: '/apps/10001/roles/roles/',
      status: 403,
      body: '<html></html>',
      expected: 'meta_session_expired',
    },
    { name: 'graphql_401', status: 401, expected: 'meta_session_expired' },
    { name: 'graphql_403', status: 403, expected: 'meta_session_expired' },
    {
      name: 'upstream_http_407_consumed_by_chromium',
      status: 407,
      // Real Chrome reports requestfailed, not an HTTP response, for this challenge.
      expected: 'meta_unavailable',
      expectedFailureCode: 'net::ERR_UNEXPECTED_PROXY_AUTH',
    },
    { name: 'graphql_429', status: 429, expected: 'rate_limited' },
    { name: 'graphql_500', status: 500, expected: 'meta_unavailable' },
    {
      name: 'graphql_invalid_json',
      body: '{invalid',
      expected: 'unknown_status',
    },
    {
      name: 'graphql_login_html',
      body: '<html><body>Log in</body></html>',
      expected: 'unknown_status',
    },
    {
      name: 'graphql_error_with_data',
      body: JSON.stringify({
        ...acceptedDocument,
        errors: [{ message: 'synthetic error' }],
      }),
      expected: 'unknown_status',
    },
    {
      name: 'roles_container_partial',
      body: JSON.stringify({
        data: {
          get_app_roles: {
            ...acceptedDocument.data.get_app_roles,
            page_info: { has_next_page: true },
          },
        },
      }),
      expected: 'unknown_status',
    },
    {
      name: 'roles_group_partial',
      body: JSON.stringify({
        data: {
          get_app_roles: {
            app_roles: [
              {
                ...acceptedDocument.data.get_app_roles.app_roles[0],
                page_info: { has_next_page: true },
              },
            ],
          },
        },
      }),
      expected: 'unknown_status',
    },
    {
      name: 'roles_conflicting_status',
      body: JSON.stringify({
        data: {
          get_app_roles: {
            app_roles: [
              {
                role: 'instagram testers',
                users: [
                  { id: fixture.target.id, status: 'CONFIRMED' },
                  { id: fixture.target.id, status: 'PENDING' },
                ],
              },
            ],
          },
        },
      }),
      expected: 'unknown_status',
    },
  ];
  for (const definition of responseCases) {
    const failedStart = requestFailures.length;
    const responseStart = responseStatuses.length;
    transport.setResponseFault({ path: '/api/graphql/', ...definition });
    const result = await operation('status_accepted');
    const faultConsumed = !transport.pendingResponseFault();
    transport.setResponseFault(null);
    const recovery = await operation('status_accepted');
    cases.push({
      name: definition.name,
      passed:
        faultConsumed &&
        result.error_code === definition.expected &&
        result.status === undefined &&
        (!definition.expectedFailureCode ||
          requestFailures
            .slice(failedStart)
            .includes(definition.expectedFailureCode)) &&
        recovery.status === 'accepted',
      expected: definition.expected,
      actual: result.error_code || null,
      result_status: result.status || null,
      recovered_status: recovery.status || null,
      recovery_error: recovery.error_code || null,
      fault_consumed: faultConsumed,
      request_failure_codes: requestFailures.slice(failedStart),
      observed_response_statuses: responseStatuses.slice(responseStart),
    });
  }

  await delay(100);
  assert.deepEqual(errors, []);
  assert.equal(cases.length, responseOnly ? 13 : 39);
  printReport(
    JSON.stringify({
      status: cases.every(value => value.passed) ? 'passed' : 'failed',
      cases,
      operations: sequence - 1,
      route_failures_contained: diagnostics.length,
      unhandled_rejections: errors.length,
      meta_called: false,
      production_profile_used: false,
      production_mutated: false,
      limits: [
        'Synthetic TLS/proxy and Meta responses; no production latency measurement.',
        'Page replacement is fixture recovery, not proof that the production manager replaces a closed page.',
      ],
    })
  );
  assert.ok(
    cases.every(value => value.passed),
    'All sad paths and recovery must pass'
  );
} finally {
  await context.close().catch(() => {});
  await browser.close().catch(() => {});
  await transport.close();
  process.removeListener('unhandledRejection', onUnhandled);
}
