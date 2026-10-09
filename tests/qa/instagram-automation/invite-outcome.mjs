/* eslint-disable no-await-in-loop, no-restricted-syntax -- Invite cases intentionally run serially on one browser page. */
// Local-only invite outcome contract: real Chrome, synthetic HTTPS origin and
// proxy. It never reaches Meta, AWS or a production profile.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { executeBrowserOperation } from '../../../scripts/instagram_testers/browser-operations.mjs';
import {
  handleBrowserRoute,
  isAllowedBrowserRequest,
} from '../../../scripts/instagram_testers/session-manager.mjs';
import {
  createFixtureHtml,
  createFixtureTransport,
  loadChromium,
  makeConfiguration,
  makeRequest,
} from './latency-benchmark.mjs';

const INVITE_PATH = '/apps/10001/async/instagram/roles/add/';
const SETTLE_POLL_MS = 100;
const SETTLE_STABLE_MS = 3000;
const OPERATION_TIMEOUT_MS = 90000;
const DEFAULT_BUDGET_MS = 85000;
const TASK_SETTLE_MS = 2000;
const SUCCESS_BODY = '{"payload":{"success":true}}';
const REJECTED_BODY = '{"payload":{"success":false}}';
const WRITE = Object.freeze({ decision: 'write', status: 'absent' });

const fixture = JSON.parse(
  await readFile(
    new URL('./latency-browser-fixtures.json', import.meta.url),
    'utf8'
  )
);
assert.equal(fixture.meta_called, false);
assert.equal(fixture.production_mutated, false);
const config = makeConfiguration(fixture);
const rolesPagePath = new URL(config.rolesUrl).pathname;

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

function permitAfter(milliseconds, fields) {
  return async observation => {
    await delay(milliseconds);
    return permitReply(observation, fields);
  };
}

// Honors the manager's per-permit transport budget and never answers.
function permitThatTimesOut() {
  return (_observation, { timeoutMs } = {}) =>
    new Promise((_resolve, reject) => {
      if (Number.isFinite(timeoutMs))
        setTimeout(() => reject(new Error('operation_timeout')), timeoutMs);
    });
}

function doublePostHtml() {
  const html = createFixtureHtml(fixture, 'invite_unknown');
  const needle =
    "    await fetch(inviteUrl, { method: 'POST', body: inviteFields() });";
  if (html.split(needle).length !== 2) throw new Error('fixture_shape_changed');
  return html.replace(
    needle,
    [
      "    fetch(inviteUrl, { method: 'POST', body: inviteFields() }).catch(() => {});",
      "    fetch(inviteUrl, { method: 'POST', body: inviteFields() }).catch(() => {});",
    ].join('\n')
  );
}

const CASES = [
  {
    name: 'slow_permit_never_reports_an_unsent_write',
    permit: permitAfter(6500, WRITE),
    fault: { path: INVITE_PATH, body: SUCCESS_BODY },
    expect: { invited: true, write_started: true, delta: 1 },
    permitSeesNoWrite: true,
  },
  {
    name: 'slow_meta_response_is_success_not_false_failure',
    permit: permitAfter(0, WRITE),
    fault: { path: INVITE_PATH, delayMs: 8000, body: SUCCESS_BODY },
    expect: { invited: true, write_started: true, delta: 1 },
  },
  {
    name: 'meta_silent_until_deadline_is_truthful_unknown',
    permit: permitAfter(0, WRITE),
    budgetMs: 25000,
    fault: { path: INVITE_PATH, delayMs: 40000, body: SUCCESS_BODY },
    expect: { error_code: 'invite_unknown', write_started: true, delta: 1 },
    returnsBeforeDeadlinePlusMs: 2000,
  },
  {
    name: 'stalled_body_after_headers_is_unknown_within_budget',
    permit: permitAfter(0, WRITE),
    budgetMs: 25000,
    fault: {
      path: INVITE_PATH,
      stallBodyAfterHeadersMs: 60000,
      body: SUCCESS_BODY,
    },
    expect: { error_code: 'invite_unknown', write_started: true, delta: 1 },
    returnsBeforeDeadlinePlusMs: TASK_SETTLE_MS + 1000,
  },
  {
    name: 'meta_rejects_invite',
    permit: permitAfter(0, WRITE),
    fault: { path: INVITE_PATH, body: REJECTED_BODY },
    expect: { error_code: 'invite_rejected', write_started: true, delta: 1 },
  },
  {
    // B5 adds the invite_response_class assertion through onTiming.
    name: 'success_missing_is_unknown',
    permit: permitAfter(0, WRITE),
    expect: { error_code: 'invite_unknown', write_started: true, delta: 1 },
  },
  {
    name: 'permit_noop_never_clicks',
    permit: permitAfter(0, { decision: 'noop', status: 'pending' }),
    expect: {
      status: 'pending',
      invited: false,
      write_started: false,
      delta: 0,
    },
    noClick: true,
  },
  {
    // Simulates a re-claim after a lost completion: another claim's marker.
    name: 'permit_denied_never_clicks',
    permit: permitAfter(0, { error_code: 'invite_unknown' }),
    expect: { error_code: 'invite_unknown', write_started: false, delta: 0 },
    noClick: true,
  },
  {
    name: 'permit_transport_times_out_never_clicks',
    permit: permitThatTimesOut(),
    budgetMs: 27000,
    expect: { error_code: 'meta_unavailable', write_started: false, delta: 0 },
    noClick: true,
    returnsWithinPermitBudgetPlusMs: 1000,
  },
  {
    name: 'budget_too_short_never_requests_permit',
    permit: permitAfter(0, WRITE),
    budgetMs: 3000,
    expect: { error_code: 'meta_unavailable', write_started: false, delta: 0 },
    noClick: true,
    noPermit: true,
  },
  {
    // B5 adds the invite_response_class assertion through onTiming.
    name: 'mid_flight_disconnect_is_unknown_fast',
    permit: permitAfter(0, WRITE),
    fault: { path: INVITE_PATH, disconnect: true },
    expect: { error_code: 'invite_unknown', write_started: true, delta: 1 },
    elapsedBelowMs: 10000,
    // Chrome re-sends a request whose reused keep-alive socket resets before
    // any response byte, below the route layer (also on the base code). The
    // page still issued one invite request; the extra hit is the transport.
    transportRetryAllowed: true,
  },
  {
    name: 'double_post_from_page_is_single_write',
    permit: permitAfter(0, WRITE),
    fault: { path: rolesPagePath, status: 200, body: doublePostHtml() },
    expect: { error_code: 'invite_unknown', write_started: true, delta: 1 },
  },
];

const selected = (process.env.INVITE_OUTCOME_CASES || '')
  .split(',')
  .filter(Boolean);
const cases = selected.length
  ? CASES.filter(definition => selected.includes(definition.name))
  : CASES;
assert.equal(cases.length, selected.length || CASES.length);

// The fixture counts an invite after reading its body, so wait until the
// count has been stable for 3 s before checking write invariants.
async function settledInviteCount(transport) {
  let last = transport.counts().invite;
  let stableSince = Date.now();
  while (Date.now() - stableSince < SETTLE_STABLE_MS) {
    await delay(SETTLE_POLL_MS);
    const current = transport.counts().invite;
    if (current !== last) {
      last = current;
      stableSince = Date.now();
    }
  }
  return last;
}

function checkCase(definition, observed) {
  const failures = [];
  const check = (name, condition) => {
    if (!condition) failures.push(name);
  };
  const { result, delta } = observed;
  check('unsent_write_has_no_post', result.write_started || delta === 0);
  if (definition.transportRetryAllowed) {
    check('one_page_invite_request', observed.pageInviteRequests === 1);
    check('post_count_with_transport_retry', delta >= 1 && delta <= 2);
  } else {
    check('at_most_one_post', delta <= 1);
    check('post_count', delta === definition.expect.delta);
  }
  check(
    'write_started',
    result.write_started === definition.expect.write_started
  );
  if (definition.expect.error_code)
    check('error_code', result.error_code === definition.expect.error_code);
  else check('no_error_code', result.error_code === undefined);
  if (definition.expect.invited !== undefined)
    check('invited', result.invited === definition.expect.invited);
  if (definition.expect.invited === true)
    check('pending_after_invite', result.status === 'pending');
  if (definition.expect.status)
    check('status', result.status === definition.expect.status);
  if (definition.permitSeesNoWrite)
    check(
      'permit_before_any_post',
      observed.permitDeltas.length === 1 && observed.permitDeltas[0] === 0
    );
  if (definition.noClick) check('no_click', !observed.clicked);
  if (definition.noPermit) check('no_permit', observed.permitCalls === 0);
  if (definition.returnsBeforeDeadlinePlusMs)
    check(
      'returns_within_deadline',
      observed.returnedAt <=
        observed.deadlineAt + definition.returnsBeforeDeadlinePlusMs
    );
  if (definition.returnsWithinPermitBudgetPlusMs)
    check(
      'returns_within_permit_budget',
      Number.isFinite(observed.permitTimeoutMs) &&
        observed.returnedAt - observed.permitStartedAt <=
          observed.permitTimeoutMs + definition.returnsWithinPermitBudgetPlusMs
    );
  if (definition.elapsedBelowMs)
    check(
      'elapsed',
      observed.returnedAt - observed.startedAt < definition.elapsedBelowMs
    );
  return failures;
}

const transport = await createFixtureTransport(fixture, ['invite_unknown']);
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
const errors = [];
const onUnhandled = () => errors.push('unhandled_rejection');
process.on('unhandledRejection', onUnhandled);
const results = [];
let marks = [];
let pageInviteRequests = 0;
try {
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  await context.route('**/*', route =>
    handleBrowserRoute(route, config, { write: () => {} })
  );
  const page = await context.newPage();
  await page.exposeFunction('__latencyMark', name => {
    if (typeof name === 'string') marks.push(name);
  });
  page.on('request', browserRequest => {
    if (new URL(browserRequest.url()).pathname === INVITE_PATH)
      pageInviteRequests += 1;
  });
  for (const [index, definition] of cases.entries()) {
    transport.setScenario('invite_unknown');
    transport.setResponseFault(definition.fault || null);
    marks = [];
    pageInviteRequests = 0;
    const before = transport.counts().invite;
    const permitDeltas = [];
    let permitCalls = 0;
    let permitStartedAt = null;
    let permitTimeoutMs = null;
    const startedAt = Date.now();
    const deadlineAt = startedAt + (definition.budgetMs || DEFAULT_BUDGET_MS);
    let result;
    try {
      result = await executeBrowserOperation({
        page,
        configuration: config,
        request: makeRequest('invite_unknown', config, fixture, index + 2),
        signal: AbortSignal.timeout(OPERATION_TIMEOUT_MS),
        deadlineAt,
        requestGuard: parameters =>
          isAllowedBrowserRequest({ ...parameters, config }),
        permitInvite: (observation, options) => {
          permitCalls += 1;
          permitStartedAt = Date.now();
          permitTimeoutMs = options?.timeoutMs ?? null;
          permitDeltas.push(transport.counts().invite - before);
          return definition.permit(observation, options);
        },
      });
    } catch (error) {
      result = { thrown: error?.name || 'Error' };
    }
    const returnedAt = Date.now();
    const delta = (await settledInviteCount(transport)) - before;
    transport.setResponseFault(null);
    const observed = {
      result,
      delta,
      startedAt,
      returnedAt,
      deadlineAt,
      permitDeltas,
      permitCalls,
      permitStartedAt,
      permitTimeoutMs,
      pageInviteRequests,
      clicked: marks.includes('invite_button_clicked'),
    };
    const failures = checkCase(definition, observed);
    results.push({
      name: definition.name,
      passed: failures.length === 0,
      failures,
      actual: {
        error_code: result.error_code ?? null,
        status: result.status ?? null,
        invited: result.invited ?? null,
        write_started: result.write_started ?? null,
        thrown: result.thrown ?? null,
        invite_delta: delta,
        page_invite_requests: pageInviteRequests,
        elapsed_ms: returnedAt - startedAt,
        returned_after_deadline_ms: returnedAt - deadlineAt,
        permit_calls: permitCalls,
        permit_deltas: permitDeltas,
        permit_timeout_ms: permitTimeoutMs,
        clicked: observed.clicked,
      },
    });
  }
  await delay(100);
} finally {
  await browser.close().catch(() => {});
  await transport.close();
  process.removeListener('unhandledRejection', onUnhandled);
}
const passed = errors.length === 0 && results.every(value => value.passed);
process.stdout.write(
  `${JSON.stringify({
    status: passed ? 'passed' : 'failed',
    benchmark: 'browser_invite_outcome_contract',
    cases: results,
    unhandled_rejections: errors.length,
    meta_called: false,
    production_profile_used: false,
    production_mutated: false,
    limits: [
      'Synthetic local HTTPS/proxy transport; the real Meta success shape is still unobserved.',
    ],
  })}\n`
);
if (!passed) process.exitCode = 1;
