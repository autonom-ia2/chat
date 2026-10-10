/*
 * Local-only browser transport contract for HTTP 407 responses.
 *
 * The upstream case returns 407 after CONNECT has succeeded. The proxy case
 * returns 407 while handling CONNECT, before any TLS or HTTP origin request.
 * Both cases use loopback-only fixture services and a fresh browser context
 * for recovery; no Meta, AWS, credentials, or production profile is used.
 */
/* eslint-disable no-await-in-loop -- Cases are intentionally ordered around lifecycle recovery. */

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
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

const GRAPHQL_PATH = '/api/graphql/';
const FIXTURE_PATH = new URL(
  './latency-browser-fixtures.json',
  import.meta.url
);
const TRANSPORT_ERROR_CODES = new Set([
  'meta_unavailable',
  'proxy_unavailable',
]);

function safeErrorCode(result) {
  return typeof result?.error_code === 'string' ? result.error_code : null;
}

function resultShape(result) {
  return {
    status: typeof result?.status === 'string' ? result.status : null,
    error_code: safeErrorCode(result),
    write_started: result?.write_started === true,
  };
}

function requestFailureCode(request) {
  const errorText = request.failure()?.errorText || '';
  return errorText.match(/net::ERR_[A-Z_]+/)?.[0] || 'unclassified';
}

function assertTransportError(outcome) {
  assert.ok(TRANSPORT_ERROR_CODES.has(outcome.result.error_code));
}

async function openContext(browser, configuration) {
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  await context.route('**/*', route =>
    handleBrowserRoute(route, configuration, { write: () => {} })
  );
  const page = await context.newPage();
  return { context, page };
}

async function runStatus(page, configuration, fixture) {
  const responseStatuses = [];
  const requestFailureCodes = [];
  const onResponse = response => {
    try {
      if (new URL(response.url()).pathname === GRAPHQL_PATH)
        responseStatuses.push(response.status());
    } catch {
      /* A malformed synthetic URL is not evidence for this case. */
    }
  };
  const onRequestFailed = request =>
    requestFailureCodes.push(requestFailureCode(request));
  page.on('response', onResponse);
  page.on('requestfailed', onRequestFailed);
  try {
    const result = await executeBrowserOperation({
      page,
      configuration,
      request: makeRequest('status_accepted', configuration, fixture, 1),
      signal: AbortSignal.timeout(8000),
      requestGuard: parameters =>
        isAllowedBrowserRequest({ ...parameters, config: configuration }),
    });
    return {
      result: resultShape(result),
      response_statuses: responseStatuses,
      request_failure_codes: requestFailureCodes,
    };
  } finally {
    page.off('response', onResponse);
    page.off('requestfailed', onRequestFailed);
  }
}

async function main() {
  const fixture = JSON.parse(await readFile(FIXTURE_PATH, 'utf8'));
  assert.equal(fixture.meta_called, false);
  assert.equal(fixture.production_mutated, false);
  const configuration = makeConfiguration(fixture);
  const transport = await createFixtureTransport(
    fixture,
    Object.keys(fixture.scenarios)
  );
  const chromium = await loadChromium();
  const executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
  assert.ok(executablePath && !executablePath.includes('\0'));
  const browser = await chromium.launch({
    headless: true,
    executablePath,
    proxy: { server: transport.proxy },
    args: [
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-sync',
    ],
  });
  let context;
  const closeContext = async () => {
    await context?.context.close().catch(() => {});
    context = null;
  };
  try {
    transport.setScenario('status_accepted');
    const upstreamFaultStart = transport.responseFaultHits();
    transport.setResponseFault({
      path: GRAPHQL_PATH,
      status: 407,
      body: '{"error":"synthetic_upstream_http_407"}',
    });
    context = await openContext(browser, configuration);
    const upstream = await runStatus(context.page, configuration, fixture);
    const upstreamFaultHits =
      transport.responseFaultHits() - upstreamFaultStart;
    assert.ok(upstreamFaultHits > 0);
    assert.equal(transport.pendingResponseFault(), false);
    assertTransportError(upstream);
    assert.notEqual(upstream.result.status, 'accepted');
    assert.equal(transport.counts().invite, 0);
    assert.ok(
      upstream.response_statuses.includes(407) ||
        upstream.request_failure_codes.length > 0
    );
    await closeContext();

    context = await openContext(browser, configuration);
    const upstreamRecovery = await runStatus(
      context.page,
      configuration,
      fixture
    );
    assert.equal(upstreamRecovery.result.status, 'accepted');
    assert.equal(transport.counts().invite, 0);
    await closeContext();

    transport.setConnectFault({ status: 407, persistent: true });
    const directChallengeStart = transport.connectFaultHits();
    const directChallenge = await transport.probeConnectChallenge();
    assert.equal(directChallenge.status, 407);
    assert.equal(transport.connectFaultHits() - directChallengeStart, 1);
    assert.equal(transport.pendingConnectFault(), true);

    const browserChallengeStart = transport.connectFaultHits();
    context = await openContext(browser, configuration);
    const connectChallenge = await runStatus(
      context.page,
      configuration,
      fixture
    );
    const browserChallengeHits =
      transport.connectFaultHits() - browserChallengeStart;
    assert.ok(browserChallengeHits > 0);
    assertTransportError(connectChallenge);
    assert.notEqual(connectChallenge.result.status, 'accepted');
    assert.equal(transport.counts().invite, 0);
    assert.ok(
      connectChallenge.response_statuses.includes(407) ||
        connectChallenge.request_failure_codes.some(code =>
          /^net::ERR_[A-Z_]+$/.test(code)
        )
    );
    await closeContext();

    transport.setConnectFault(null);
    context = await openContext(browser, configuration);
    const connectRecovery = await runStatus(
      context.page,
      configuration,
      fixture
    );
    assert.equal(connectRecovery.result.status, 'accepted');
    assert.equal(transport.pendingConnectFault(), false);
    assert.equal(transport.counts().invite, 0);

    process.stdout.write(
      `${JSON.stringify({
        status: 'passed',
        production_mutated: false,
        meta_called: false,
        browser_lifecycle_restarted: true,
        upstream_http_407: {
          fault_hits: upstreamFaultHits,
          response_statuses: upstream.response_statuses,
          request_failure_codes: upstream.request_failure_codes,
          result: upstream.result,
          recovery_status: upstreamRecovery.result.status,
        },
        proxy_connect_407: {
          direct_status: directChallenge.status,
          browser_fault_hits: browserChallengeHits,
          response_statuses: connectChallenge.response_statuses,
          request_failure_codes: connectChallenge.request_failure_codes,
          result: connectChallenge.result,
          recovery_status: connectRecovery.result.status,
        },
      })}\n`
    );
  } finally {
    await closeContext();
    await browser.close().catch(() => {});
    await transport.close();
  }
}

main().catch(error => {
  process.stdout.write(
    `${JSON.stringify({
      status: 'failed',
      error_class: error?.name || 'Error',
      source_line:
        Number(
          error?.stack?.match(/proxy-failures\.mjs:([0-9]+):[0-9]+/)?.[1]
        ) || null,
      actual:
        typeof error.actual === 'boolean' || typeof error.actual === 'number'
          ? error.actual
          : null,
      expected:
        typeof error.expected === 'boolean' ||
        typeof error.expected === 'number'
          ? error.expected
          : null,
      production_mutated: false,
      meta_called: false,
    })}\n`
  );
  process.exitCode = 1;
});
