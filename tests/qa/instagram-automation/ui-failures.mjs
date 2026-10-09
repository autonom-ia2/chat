/* eslint-disable no-await-in-loop, no-restricted-syntax -- Cases intentionally run serially on one browser page. */

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { executeBrowserOperation } from '../../../scripts/instagram_testers/browser-operations.mjs';
import {
  handleBrowserRoute,
  isAllowedBrowserRequest,
} from '../../../scripts/instagram_testers/session-manager.mjs';
import { isMainModule } from '../../../scripts/instagram_testers/runtime/entrypoint.mjs';
import {
  createFixtureHtml,
  createFixtureTransport,
  loadChromium,
  makeConfiguration,
  makeRequest,
} from './latency-benchmark.mjs';

const FIXTURE_PATH = new URL(
  './latency-browser-fixtures.json',
  import.meta.url
);
const CASE_TIMEOUT_MS = 2000;
const SCENARIOS = ['search', 'status_accepted', 'invite_unknown'];

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
  const value = error?.code;
  return typeof value === 'string' && /^[a-z][a-z0-9_]{0,95}$/.test(value)
    ? value
    : null;
}

function safeScalar(value) {
  if (
    value === null ||
    typeof value === 'boolean' ||
    (typeof value === 'number' && Number.isFinite(value))
  )
    return value;
  if (typeof value === 'string' && /^[A-Za-z0-9_.:@/-]{0,120}$/.test(value))
    return value;
  return null;
}

function actualError(result, error) {
  if (typeof result?.error_code === 'string') return result.error_code;
  return safeCode(error) || (error ? safeClass(error) : null);
}

function assertionFailure(name, error) {
  return {
    name,
    error_class: safeClass(error),
    error_code: safeCode(error),
    expected: safeScalar(error?.expected),
    actual: safeScalar(error?.actual),
  };
}

function replaceOnce(source, needle, replacement) {
  const occurrences = source.split(needle).length - 1;
  if (occurrences !== 1) fail('fixture_shape_changed');
  return source.replace(needle, replacement);
}

function baseHtml(fixture) {
  return createFixtureHtml(fixture, 'invite_unknown');
}

function twoAddButtonsHtml(fixture) {
  const html = baseHtml(fixture);
  const addButton =
    '    <button type="button" id="add-people">Add people</button>';
  return replaceOnce(
    html,
    addButton,
    `${addButton}\n    <button type="button">Add people</button>`
  );
}

function twoComboboxesHtml(fixture) {
  const html = baseHtml(fixture);
  const combobox =
    '      <input id="tester-search" type="text" role="combobox" aria-controls="latency-listbox" autocomplete="off">';
  return replaceOnce(
    html,
    combobox,
    `${combobox}\n      <input type="text" role="combobox" aria-controls="latency-listbox" autocomplete="off">`
  );
}

function twoExactOptionsHtml(fixture) {
  const html = baseHtml(fixture);
  return replaceOnce(
    html,
    '      listbox.append(option);',
    '      listbox.append(option, option.cloneNode(true));'
  );
}

function hiddenOptionHtml(fixture) {
  const html = baseHtml(fixture);
  return replaceOnce(
    html,
    '      listbox.append(option);',
    '      option.hidden = true;\n      listbox.append(option);'
  );
}

function disabledOptionHtml(fixture) {
  const html = baseHtml(fixture);
  return replaceOnce(
    html,
    '      listbox.append(option);',
    "      option.setAttribute('aria-disabled', 'true');\n      listbox.append(option);"
  );
}

function loginWithoutRolesHtml(fixture) {
  const html = baseHtml(fixture);
  const bodyStart = html.indexOf('<body>');
  const bodyEnd = html.lastIndexOf('</body>');
  if (bodyStart < 0 || bodyEnd <= bodyStart) fail('fixture_shape_changed');
  return `${html.slice(0, bodyStart)}<body><main><p>Login</p></main></body>${html.slice(
    bodyEnd + '</body>'.length
  )}`;
}

function difference(after, before) {
  return Object.fromEntries(
    Object.keys(after).map(key => [key, after[key] - (before[key] || 0)])
  );
}

function permitDenied(observation) {
  return {
    type: 'browser_operation',
    operation: 'invite_permit',
    id: observation.id,
    request_id: observation.request_id,
    claim: observation.claim,
    error_code: 'invalid_selection',
  };
}

async function operation({
  page,
  configuration,
  fixture,
  scenario,
  iteration,
  signal,
  onDiagnostic,
}) {
  const request = makeRequest(scenario, configuration, fixture, iteration);
  return executeBrowserOperation({
    page,
    configuration,
    request,
    signal,
    onDiagnostic,
    requestGuard: parameters =>
      isAllowedBrowserRequest({ ...parameters, config: configuration }),
    permitInvite: scenario === 'invite_unknown' ? permitDenied : undefined,
  });
}

const CASES = [
  {
    name: 'two_add_buttons',
    html: twoAddButtonsHtml,
    expectedError: 'meta_unavailable',
    expectedPhase: 'add_people_button',
    expectedCounts: { roles: 1, typeahead: 0 },
  },
  {
    name: 'two_comboboxes',
    html: twoComboboxesHtml,
    expectedError: 'meta_unavailable',
    expectedPhase: 'search_input',
    expectedCounts: { roles: 1, typeahead: 0 },
  },
  {
    name: 'two_exact_options',
    html: twoExactOptionsHtml,
    expectedError: 'invalid_selection',
    // The executor rejects the ambiguous result at the typeahead/selection
    // boundary before any invite request is armed.
    expectedPhase: 'typeahead_response',
    expectedCounts: { roles: 1, typeahead: 1 },
  },
  {
    name: 'hidden_option',
    html: hiddenOptionHtml,
    expectedError: 'invalid_selection',
    expectedPhase: 'typeahead_response',
    expectedCounts: { roles: 1, typeahead: 1 },
  },
  {
    name: 'disabled_option',
    html: disabledOptionHtml,
    expectedError: 'invalid_selection',
    expectedPhase: 'typeahead_response',
    expectedCounts: { roles: 1, typeahead: 1 },
  },
  {
    name: 'html_login_without_roles',
    html: loginWithoutRolesHtml,
    expectedError: 'meta_unavailable',
    expectedPhase: 'roles_capture',
    expectedCounts: { roles: 0, typeahead: 0 },
  },
];

async function runCases(fixture) {
  assert.equal(fixture.production_mutated, false);
  assert.equal(fixture.meta_called, false);
  const configuration = makeConfiguration(fixture);
  let transport;
  let browser;
  let context;
  const results = [];
  let allPassed = true;
  try {
    transport = await createFixtureTransport(fixture, SCENARIOS);
    const chromium = await loadChromium();
    const executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
    if (!executablePath || executablePath.includes('\0'))
      fail('playwright_executable_missing');
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
    context = await browser.newContext({ ignoreHTTPSErrors: true });
    await context.route('**/*', route =>
      handleBrowserRoute(route, configuration, process.stderr)
    );
    const page = await context.newPage();
    for (const [index, testCase] of CASES.entries()) {
      transport.setScenario('invite_unknown');
      const rolesPagePath = new URL(configuration.rolesUrl).pathname;
      transport.setResponseFault({
        path: rolesPagePath,
        status: 200,
        body: testCase.html(fixture),
      });
      const before = transport.counts();
      const diagnostics = [];
      let failure;
      let failureThrown;
      try {
        failure = await operation({
          page,
          configuration,
          fixture,
          scenario: 'invite_unknown',
          iteration: index + 1,
          signal: AbortSignal.timeout(CASE_TIMEOUT_MS),
          onDiagnostic: value => diagnostics.push(value),
        });
      } catch (error) {
        failureThrown = error;
      }
      const after = transport.counts();
      const failedDelta = difference(after, before);
      const expectationFailures = [];
      const check = (name, callback) => {
        try {
          callback();
        } catch (error) {
          expectationFailures.push(assertionFailure(name, error));
        }
      };
      check('response_fault_consumed', () =>
        assert.equal(transport.pendingResponseFault(), false)
      );
      check('diagnostic_count', () => assert.equal(diagnostics.length, 1));
      check('failure_phase', () =>
        assert.equal(diagnostics.at(-1)?.phase, testCase.expectedPhase)
      );
      check('roles_post_count', () =>
        assert.equal(
          diagnostics.at(-1)?.roles_request_count,
          testCase.expectedCounts.roles
        )
      );
      check('typeahead_post_count', () =>
        assert.equal(
          diagnostics.at(-1)?.typeahead_request_count,
          testCase.expectedCounts.typeahead
        )
      );
      check('failure_error', () =>
        assert.equal(failure?.error_code, testCase.expectedError)
      );
      check('failure_has_no_status', () =>
        assert.equal(failure?.status, undefined)
      );
      check('failure_has_no_results', () =>
        assert.equal(Array.isArray(failure?.results), false)
      );
      check('failure_has_no_write', () =>
        assert.equal(failure?.write_started, false)
      );
      check('invite_post_blocked', () => assert.equal(failedDelta.invite, 0));

      transport.setScenario('status_accepted');
      const recoveryBefore = transport.counts();
      let accepted;
      let recoveryThrown;
      try {
        accepted = await operation({
          page,
          configuration,
          fixture,
          scenario: 'status_accepted',
          iteration: index + 1,
          signal: AbortSignal.timeout(CASE_TIMEOUT_MS),
        });
      } catch (error) {
        recoveryThrown = error;
      }
      const recoveryAfter = transport.counts();
      const recoveryDelta = difference(recoveryAfter, recoveryBefore);
      check('recovery_status', () =>
        assert.equal(accepted?.status, 'accepted')
      );
      check('recovery_has_no_error', () =>
        assert.equal(accepted?.error_code, undefined)
      );
      const passed =
        !failureThrown && !recoveryThrown && expectationFailures.length === 0;
      if (!passed) allPassed = false;
      results.push({
        name: testCase.name,
        passed,
        expected: {
          failure_error: testCase.expectedError,
          failure_phase: testCase.expectedPhase,
          failure_roles_posts: testCase.expectedCounts.roles,
          failure_typeahead_posts: testCase.expectedCounts.typeahead,
        },
        actual: {
          failure_error: actualError(failure, failureThrown),
          failure_phase: diagnostics.at(-1)?.phase || null,
          diagnostic_error: diagnostics.at(-1)?.error_code || null,
          operation_threw: Boolean(failureThrown),
          operation_error_class: failureThrown
            ? safeClass(failureThrown)
            : null,
          failure_post_counts: failedDelta,
        },
        recovery: {
          attempted: true,
          passed: !recoveryThrown && accepted?.status === 'accepted',
          status: safeScalar(accepted?.status),
          error: actualError(accepted, recoveryThrown),
          error_class: recoveryThrown ? safeClass(recoveryThrown) : null,
          post_counts: recoveryDelta,
        },
        expectation_failures: expectationFailures,
      });
    }
    return { results, allPassed };
  } finally {
    await context?.close().catch(() => {});
    await browser?.close().catch(() => {});
    await transport?.close();
  }
}

async function main() {
  const fixture = JSON.parse(await readFile(FIXTURE_PATH, 'utf8'));
  const report = await runCases(fixture);
  const status = report.allPassed ? 'passed' : 'failed';
  process.stdout.write(
    `${JSON.stringify({
      status,
      benchmark: 'browser_ui_failure_contract',
      production_mutated: false,
      meta_called: false,
      case_timeout_ms: CASE_TIMEOUT_MS,
      cases: report.results,
      limits: [
        'Synthetic local HTTPS/proxy transport; no Meta, AWS or production profile.',
        'The short timeout bounds ambiguous UI and missing Roles responses; it does not prove a provider timeout budget.',
      ],
    })}\n`
  );
  if (!report.allPassed) process.exitCode = 1;
}

if (isMainModule(import.meta.url))
  main().catch(error => {
    process.stdout.write(
      `${JSON.stringify({
        status: 'error',
        error_class: safeClass(error),
        error_code: safeCode(error),
        production_mutated: false,
        meta_called: false,
      })}\n`
    );
    process.exitCode = 1;
  });
