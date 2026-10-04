/* eslint-disable no-await-in-loop, no-restricted-syntax -- CLI browser cases and fixture transitions must run sequentially in the exclusive database slot. */
/* eslint-disable no-console -- Standalone CLI prints only sanitized final receipts, never credentials. */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { MINIMUM_TEXT_CONTRAST } from '../instagram-testers/visual-helpers.mjs';

const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../..'
);
const output = path.join(root, 'tmp/950-integration/visual');
const marker = path.join(root, 'tmp/950-integration/browser-ready.json');
const statusFile = path.join(output, 'vega-ready.md');
fs.mkdirSync(output, { recursive: true });
const instructions =
  'Harness real Rails/ERB + Playwright preparado. Execução serial exige browser-ready.json, public/vite-test/.vite/manifest.json, PLAYWRIGHT_MODULE_PATH e PLAYWRIGHT_EXECUTABLE_PATH. Não instala dependências. Não valida E2E Meta nem produção.';
if (!fs.existsSync(marker)) {
  fs.writeFileSync(
    statusFile,
    `READY — não executado\n\n${instructions}\n\nAguardando janela de banco do coordenador; nenhum processo Rails/browser foi iniciado.\n`
  );
  console.log(
    'READY: harness preparado; browser-ready.json ausente. Banco não utilizado.'
  );
  process.exit(0);
}

const base = 'http://127.0.0.1:39510';
const capability = crypto.randomBytes(32).toString('hex');
// Local file reads only; no Git command during the exclusive browser slot.
function readHead() {
  const pointer = fs.readFileSync(path.join(root, '.git'), 'utf8').trim();
  const directory = path.resolve(root, pointer.slice('gitdir: '.length));
  const head = fs.readFileSync(path.join(directory, 'HEAD'), 'utf8').trim();
  if (!head.startsWith('ref: ')) return head;
  const common = path.resolve(
    directory,
    fs.readFileSync(path.join(directory, 'commondir'), 'utf8').trim()
  );
  return fs
    .readFileSync(path.join(common, head.slice('ref: '.length)), 'utf8')
    .trim();
}
const report = {
  kind: 'frontend Rails/ERB integration with synthetic manager evidence; not Meta E2E',
  started_at: new Date().toISOString(),
  head: readHead(),
  head_source: 'local worktree reference file; no Git subprocess',
  cases: [],
  receipts: [],
  screenshots: [],
  console: [],
  source_hashes: {},
};
const sourcePaths = [
  'app/controllers/super_admin/instagram_automations_controller.rb',
  'app/helpers/super_admin/instagram_automation_helper.rb',
  'app/services/instagram/automation/local_status.rb',
  'app/services/instagram/automation/operator_control.rb',
  'app/services/instagram/automation/metadata.rb',
  'app/views/super_admin/instagram_automation/show.html.erb',
  'app/controllers/super_admin/accounts_controller.rb',
  'app/fields/instagram_assisted_onboarding_field.rb',
  'app/views/fields/instagram_assisted_onboarding_field/_form.html.erb',
  'config/locales/en.yml',
  'config/locales/pt_BR.yml',
  'config/routes.rb',
  'tests/qa/instagram-testers/visual-helpers.mjs',
  'tests/qa/instagram-automation/server.rb',
  'tests/qa/instagram-automation/run.mjs',
];
const hash = relative =>
  crypto
    .createHash('sha256')
    .update(fs.readFileSync(path.join(root, relative)))
    .digest('hex');
let server;
let browser;
let context;
let page;
let bootstrap;
let currentCase;
const pause = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });
const clean = text =>
  [
    bootstrap?.password,
    bootstrap?.admin_email,
    bootstrap?.account_email,
    capability,
  ]
    .filter(Boolean)
    .reduce(
      (value, secret) => value.split(secret).join('[redacted]'),
      String(text)
    );
const check = (condition, description) => {
  assert.ok(condition, description);
  currentCase.checks.push(description);
};
const equal = (actual, expected, description) => {
  assert.deepEqual(actual, expected, description);
  currentCase.checks.push(description);
};
// Function declarations intentionally support the shared assertion/capture workflow.
async function scenario(name, operation) {
  currentCase = { name, status: 'running', checks: [] };
  report.cases.push(currentCase);
  try {
    await operation();
    currentCase.status = 'passed';
  } catch (error) {
    currentCase.status = 'failed';
    currentCase.error = clean(error.message);
    // Never capture login, password forms or the fixture capability.
    if (
      page &&
      (await page.locator('input[type="password"]').count()) === 0 &&
      ((await page.locator('#instagram-automation').count()) > 0 ||
        new URL(page.url()).pathname.startsWith('/super_admin/accounts/'))
    ) {
      try {
        // eslint-disable-next-line no-use-before-define -- Shared capture function is declared below.
        await screenshot(`failure-${name.slice(0, 2)}`);
      } catch (captureError) {
        currentCase.capture_error = clean(captureError.message);
      }
    }
  }
}
async function fixture(endpoint, data) {
  const response = await fetch(`${base}/__qa/${endpoint}`, {
    method: data ? 'POST' : 'GET',
    headers: {
      'x-qa-capability': capability,
      'content-type': 'application/json',
    },
    body: data ? JSON.stringify(data) : undefined,
  });
  assert.equal(response.status, 200, `fixture ${endpoint} status`);
  const value = await response.json();
  if (endpoint === 'receipt') {
    report.service_receipts ||= [];
    report.service_receipts.push({
      observed_at: new Date().toISOString(),
      ...value,
    });
  }
  return value;
}
async function visit() {
  const response = await page.goto(`${base}/super_admin/instagram_automation`);
  equal(response.status(), 200, 'real automation page HTTP 200');
  await page.locator('#instagram-automation').waitFor();
}
const saveForm = () =>
  page.locator('form[action="/super_admin/instagram_automation"]');
const reconnectButton = () =>
  page.locator(
    'form[action="/super_admin/instagram_automation/reconnect"] button'
  );
const accountCheckbox = () =>
  page.locator(
    'input[type="checkbox"][name="account[feature_instagram_assisted_onboarding]"], input[type="checkbox"][name="enabled_features[feature_instagram_assisted_onboarding]"]'
  );
async function submit(form) {
  const wait = page.waitForNavigation({ waitUntil: 'load' });
  await form.locator('button[type="submit"], input[type="submit"]').click();
  return wait;
}
async function state(value) {
  await fixture('state', { state: value });
  await visit();
}
async function screenshot(name) {
  const target = path.join(output, `${name}.png`);
  const focus = {
    'desktop-unknown-light': '[data-component="manager"]',
    'desktop-queued-light': '[data-request-state="queued"]',
    'desktop-running-light': '[data-request-state="running"]',
    'desktop-failed-light': '[data-request-state="failed"]',
    'desktop-succeeded-light': '[data-request-state="succeeded"]',
  }[name];
  if (focus) {
    const region = page.locator(focus);
    await region.scrollIntoViewIfNeeded();
    check(await region.isVisible(), 'status region visible before PNG');
    if (name !== 'desktop-unknown-light') {
      const requestState = await region.getAttribute('data-request-state');
      check(
        (await region.innerText()).includes(
          bootstrap.translations.requests[requestState].label
        ),
        'state label visible before PNG'
      );
      const visible = await region.evaluate(element => {
        const box = element.getBoundingClientRect();
        return (
          box.top >= 0 &&
          box.bottom <= window.innerHeight &&
          box.left >= 0 &&
          box.right <= window.innerWidth
        );
      });
      check(visible, 'entire request region in viewport before PNG');
    }
  }
  const bytes = await page.screenshot({
    path: target,
    fullPage: !focus,
    animations: 'disabled',
  });
  report.screenshots.push({
    path: path.relative(root, target),
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    viewport: page.viewportSize(),
    source: 'real Rails/ERB page and real Vite build',
    sha256: hash(path.relative(root, target)),
  });
}

function hashAssets(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) hashAssets(filename);
    else if (['.js', '.css', '.json'].includes(path.extname(filename))) {
      const relative = path.relative(root, filename);
      report.source_hashes[relative] = hash(relative);
    }
  }
}

try {
  assert.ok(
    process.env.PLAYWRIGHT_MODULE_PATH,
    'PLAYWRIGHT_MODULE_PATH required'
  );
  assert.ok(
    fs.existsSync(process.env.PLAYWRIGHT_EXECUTABLE_PATH || ''),
    'cached PLAYWRIGHT_EXECUTABLE_PATH required'
  );
  assert.ok(
    fs.existsSync(path.join(root, 'public/vite-test/.vite/manifest.json')),
    'real Vite test build missing'
  );
  for (const source of sourcePaths) report.source_hashes[source] = hash(source);
  const assetRoot = path.join(root, 'public/vite-test');

  hashAssets(assetRoot);
  const require = createRequire(import.meta.url);
  const { chromium } = require(process.env.PLAYWRIGHT_MODULE_PATH);
  const privateLog = fs.openSync(
    path.join(output, 'server.private.log'),
    'w',
    0o600
  );
  server = spawn(
    path.join(root, 'tmp/950-integration/run-local.sh'),
    [
      'env',
      `INSTAGRAM_QA_CAPABILITY=${capability}`,
      'ruby',
      'tests/qa/instagram-automation/server.rb',
    ],
    { cwd: root, stdio: ['ignore', privateLog, privateLog] }
  );
  fs.closeSync(privateLog);
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null)
      throw new Error(
        `QA Rack server exited ${server.exitCode}; inspect private local log`
      );
    try {
      bootstrap = await fixture('bootstrap');
      break;
    } catch {
      await pause(250);
    }
  }
  assert.ok(bootstrap, 'QA Rack startup exceeded 60s');
  report.synthetic = {
    namespace: bootstrap.namespace,
    super_admin_id: bootstrap.admin_id,
    account_id: bootstrap.account_id,
  };
  browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH,
    headless: true,
  });
  context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    locale: 'pt-BR',
    colorScheme: 'light',
  });
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.origin === base) route.continue();
    else {
      report.console.push({ type: 'remote_blocked', origin: url.origin });
      route.abort('blockedbyclient');
    }
  });
  page = await context.newPage();
  page.setDefaultTimeout(10_000);
  page.on('pageerror', error =>
    report.console.push({ type: 'pageerror', message: clean(error.message) })
  );
  let expected422Events = 0;
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const location = message.location();
    // Chromium's exact HTTP diagnostic for the deliberately invalid HTML form is expected.
    const expected =
      location.url === `${base}/super_admin/instagram_automation` &&
      message.text() ===
        'Failed to load resource: the server responded with a status of 422 (Unprocessable Content)' &&
      currentCase?.name.startsWith('05 ');
    if (expected && expected422Events === 0) {
      expected422Events += 1;
      report.receipts.push({
        type: 'expected_console_http',
        path: '/super_admin/instagram_automation',
        status: 422,
      });
    } else
      report.console.push({
        type: 'error',
        message: clean(message.text()),
        path: location.url ? new URL(location.url).pathname : null,
      });
  });
  page.on('response', response => {
    const url = new URL(response.url());
    if (url.origin === base && !url.pathname.startsWith('/__qa/')) {
      report.receipts.push({
        method: response.request().method(),
        path: url.pathname,
        status: response.status(),
      });
    }
  });
  const t = bootstrap.translations;
  const values = {
    INSTAGRAM_META_DEVELOPER_APP_ID: '950001',
    INSTAGRAM_META_BUSINESS_ID: '950002',
    INSTAGRAM_TESTER_APP_NAME: 'empresa_demo QA950',
    INSTAGRAM_TESTER_ADMIN_USER_ID: '950003',
    INSTAGRAM_TESTER_ROLES_DOC_ID: '950004',
  };

  await scenario(
    '01 Anonymous direct route requires real SuperAdmin sign-in',
    async () => {
      await page.goto(`${base}/super_admin/instagram_automation`);
      equal(
        new URL(page.url()).pathname,
        '/super_admin/sign_in',
        'anonymous redirected to Devise login'
      );
      equal(
        await page.locator('#instagram-automation').count(),
        0,
        'protected content absent'
      );
      check(
        (await page.locator('input[name="authenticity_token"]').count()) > 0,
        'real Devise form contains CSRF token'
      );
    }
  );
  await scenario('02 Real Devise login then Settings navigation', async () => {
    await page.locator('#super_admin_email').fill(bootstrap.admin_email);
    await page.locator('#super_admin_password').fill(bootstrap.password);
    await submit(page.locator('form[action="/super_admin/sign_in"]'));
    check(
      new URL(page.url()).pathname !== '/super_admin/sign_in',
      'real credentials authenticated'
    );
    const response = await page.goto(`${base}/super_admin/settings`);
    equal(response.status(), 200, 'Settings rendered by real Rails');
    const links = page.locator('a[href="/super_admin/instagram_automation"]');
    check(
      (await links.count()) >= 2,
      'Settings card and navigation link exist'
    );
    const sdkBefore = (await fixture('receipt')).support_sdk_requests;
    await links.last().click();
    await page.locator('#instagram-automation').waitFor();
    equal(
      (await fixture('receipt')).support_sdk_requests,
      sdkBefore,
      'automation optout makes zero support SDK requests'
    );
    equal(
      await page.evaluate(() => typeof window.chatwootSDK),
      'undefined',
      'automation page has no support SDK runtime'
    );
    equal(
      await page
        .locator('details[open] a[href="/super_admin/instagram_automation"]')
        .count(),
      1,
      'Settings submenu stays open'
    );
  });
  await scenario(
    '03 Five labeled metadata inputs and OAuth distinction',
    async () => {
      await visit();
      equal(
        await saveForm().locator('input[type="text"]').count(),
        5,
        'exactly five metadata inputs'
      );
      for (const key of Object.keys(values)) {
        const input = page.locator(`#instagram_automation_${key}`);
        equal(await input.count(), 1, `${key} has one input`);
        const id = await input.getAttribute('id');
        check(
          await page.locator(`label[for="${id}"]`).textContent(),
          `${key} has visible label`
        );
        const hint = await input.getAttribute('aria-describedby');
        check(
          hint && (await page.locator(`#${hint}`).textContent()),
          `${key} has associated hint`
        );
      }
      const text = await page.locator('#instagram-automation').innerText();
      check(
        text.includes('Meta Developer App ID') &&
          text.includes('Instagram App ID') &&
          text.includes('OAuth'),
        'parent App is distinguished from Instagram OAuth App'
      );
      check(
        text.includes('RolesTable') && text.includes('doc_id'),
        'advanced RolesTable identifier explained'
      );
      equal(
        await page
          .locator(
            '#instagram-automation select, #instagram-automation style, #instagram-automation [style]'
          )
          .count(),
        0,
        'no native selects or custom styles inside product panel'
      );
    }
  );
  await scenario(
    '04 Save all five metadata through HTML form and persist reload',
    async () => {
      await visit();
      for (const [key, value] of Object.entries(values))
        await page.locator(`#instagram_automation_${key}`).fill(value);
      await submit(saveForm());
      equal(
        await page.locator('.flash-notice').innerText(),
        t.saved,
        'localized saved toast is exact'
      );
      equal(
        (await fixture('receipt')).metadata,
        values,
        'all five exact values persisted'
      );
      await visit();
      for (const [key, value] of Object.entries(values))
        equal(
          await page.locator(`#instagram_automation_${key}`).inputValue(),
          value,
          `${key} kept after reload`
        );
    }
  );
  await scenario(
    '05 Invalid HTML gives 422, keeps stored values and safe valid edits',
    async () => {
      await visit();
      await page
        .locator('#instagram_automation_INSTAGRAM_META_BUSINESS_ID')
        .fill('<script>invalid</script>');
      await page
        .locator('#instagram_automation_INSTAGRAM_TESTER_APP_NAME')
        .fill('empresa_demo safe edit');
      const response = await submit(saveForm());
      equal(response.status(), 422, 'invalid HTML returns 422');
      check(
        (await page.locator('[role="alert"]').innerText()).includes(
          t.invalid_configuration
        ),
        'localized fixed validation error'
      );
      equal(
        await page
          .locator('#instagram_automation_INSTAGRAM_META_BUSINESS_ID')
          .inputValue(),
        values.INSTAGRAM_META_BUSINESS_ID,
        'malformed value replaced by saved value'
      );
      equal(
        await page
          .locator('#instagram_automation_INSTAGRAM_TESTER_APP_NAME')
          .inputValue(),
        'empresa_demo safe edit',
        'safe valid edit preserved for correction'
      );
      equal(
        (await fixture('receipt')).metadata,
        values,
        'invalid submission causes no partial writes'
      );
      equal(
        report.receipts.filter(
          receipt =>
            receipt.method === 'POST' &&
            receipt.path === '/super_admin/instagram_automation' &&
            receipt.status === 422
        ).length,
        1,
        'one real HTML save response is HTTP 422'
      );
    }
  );
  await scenario(
    '06 Missing CSRF blocks all three mutation endpoints',
    async () => {
      for (const endpoint of ['', '/health', '/reconnect']) {
        const response = await context.request.post(
          `${base}/super_admin/instagram_automation${endpoint}`,
          {
            headers: { accept: 'application/json' },
            data: endpoint
              ? {}
              : {
                  instagram_automation: {
                    INSTAGRAM_TESTER_APP_NAME: 'CSRF must not save',
                  },
                },
          }
        );
        equal(
          response.status(),
          422,
          `${endpoint || 'save'} missing CSRF blocked`
        );
        equal(
          await response.json(),
          { error: 'invalid_request' },
          'fixed CSRF error without echo'
        );
      }
      equal(
        (await fixture('receipt')).metadata,
        values,
        'missing CSRF leaves metadata unchanged'
      );
    }
  );
  await scenario('07 Unknown manager has no reconnect promise', async () => {
    await state('unknown');
    const receipt = await fixture('receipt');
    equal(
      receipt.status.manager_connectivity,
      'unknown',
      'real LocalStatus sees missing heartbeat as unknown'
    );
    check(
      await reconnectButton().isDisabled(),
      'unknown manager reconnect is disabled'
    );
    const cards = await page.locator('[role="status"]').innerText();
    check(cards.includes(t.states.unknown.label), 'unknown is displayed');
    check(
      cards.includes(t.states.configured.label),
      'configured remains separate'
    );
    check(
      !cards.includes(t.states.healthy.label),
      'configuration does not claim healthy'
    );
    await screenshot('desktop-unknown-light');
  });
  await scenario(
    '08 Operator disconnected keeps reconnect disabled',
    async () => {
      await state('operator_disconnected');
      equal(
        (await fixture('receipt')).status.control_available,
        false,
        'real control channel unavailable'
      );
      check(
        await reconnectButton().isDisabled(),
        'disconnected operator has no false button promise'
      );
    }
  );
  await scenario('09 Manager healthy does not prove Meta health', async () => {
    await fixture('state', { state: 'healthy' });
    const before = await fixture('receipt');
    await visit();
    const receipt = await fixture('receipt');
    equal(
      receipt.status.manager_connectivity,
      'healthy',
      'synthetic heartbeat read by real service'
    );
    equal(receipt.status.meta_connectivity, 'unknown', 'Meta remains unknown');
    check(
      await reconnectButton().isDisabled(),
      'healthy manager needs no reconnect'
    );
    const cards = page.locator('[role="status"] > div');
    equal(await cards.count(), 6, 'six separate evidence cards');
    check(
      (await cards.nth(2).innerText()).includes(
        t.states.heartbeat_present.label
      ),
      'manager card describes stored heartbeat evidence'
    );
    equal(
      Date.parse(
        await page
          .locator('[data-component="manager"] time')
          .getAttribute('datetime')
      ),
      Date.parse(receipt.status.manager.observed_at),
      'manager timestamp exactly matches independent heartbeat ISO3 source'
    );
    check(
      (await cards.nth(5).innerText()).includes(t.states.unknown.label),
      'Meta card shows unknown'
    );
    const localDatetime = await page
      .locator('section[aria-labelledby="instagram-health-title"] > div time')
      .first()
      .getAttribute('datetime');
    const localTime = Date.parse(localDatetime);
    const beforeTime = Date.parse(before.status.checked_at);
    const receiptTime = Date.parse(receipt.status.checked_at);
    currentCase.timestamp_evidence = {
      before_datetime: before.status.checked_at,
      before_ms: beforeTime,
      page_datetime: localDatetime,
      page_ms: localTime,
      after_datetime: receipt.status.checked_at,
      after_ms: receiptTime,
    };
    check(
      Number.isFinite(localTime),
      'local inspection timestamp is valid ISO'
    );
    check(
      Number.isFinite(beforeTime) &&
        Number.isFinite(receiptTime) &&
        beforeTime <= localTime &&
        localTime <= receiptTime,
      `rendered local inspection timestamp lies within independent receipts bracketing PageGET: ${before.status.checked_at} (${beforeTime}) <= ${localDatetime} (${localTime}) <= ${receipt.status.checked_at} (${receiptTime})`
    );
  });
  await scenario(
    '10 Local health POST supplies localized receipt without metadata writes',
    async () => {
      await visit();
      const before = await fixture('receipt');
      await submit(
        page.locator('form[action="/super_admin/instagram_automation/health"]')
      );
      equal(
        await page.locator('.flash-notice').innerText(),
        t.health_checked,
        'health flash describes local inspection'
      );
      const after = await fixture('receipt');
      equal(after.metadata, before.metadata, 'health does not mutate metadata');
      equal(
        after.status.meta_connectivity,
        'unknown',
        'health does not fabricate Meta success'
      );
    }
  );
  await scenario(
    '11 Reconnect is queued via real controller with operator evidence',
    async () => {
      await state('operator_available');
      check(
        await reconnectButton().isEnabled(),
        'reconnect enabled by both valid signals'
      );
      await submit(
        page.locator(
          'form[action="/super_admin/instagram_automation/reconnect"]'
        )
      );
      equal(
        await page.locator('.flash-notice').innerText(),
        t.reconnect_queued,
        'toast says queued, never reconnected'
      );
      const request = (await fixture('receipt')).status.control;
      equal(request.state, 'queued', 'real OperatorControl request queued');
      equal(request.action, 'reconnect', 'typed action retained');
      equal(
        String(request.actor_id),
        String(bootstrap.admin_id),
        'actor supplied from authenticated SuperAdmin'
      );
      check(
        Date.parse(request.created_at) > 0 &&
          Date.parse(request.updated_at) > 0,
        'request has source timestamps'
      );
      check(
        await reconnectButton().isDisabled(),
        'queued operation prevents duplicate click'
      );
      await screenshot('desktop-queued-light');
    }
  );
  await scenario(
    '12 Running and failed progress visible with real transitions',
    async () => {
      await state('running');
      equal(
        (await fixture('receipt')).status.control.state,
        'running',
        'real request claimed'
      );
      check(
        (
          await page.locator('[data-request-state="running"]').innerText()
        ).includes(t.requests.running.label),
        'running progress is visible'
      );
      check(
        await reconnectButton().isDisabled(),
        'running request blocks repeat'
      );
      await screenshot('desktop-running-light');
      await state('failed');
      equal(
        (await fixture('receipt')).status.control.state,
        'failed',
        'real terminal failure preserved'
      );
      check(
        (
          await page.locator('[data-request-state="failed"]').innerText()
        ).includes(t.requests.failed.label),
        'failed progress is visible'
      );
      await screenshot('desktop-failed-light');
    }
  );
  await scenario(
    '13 Retry and succeeded is source-valid without claiming Meta alive',
    async () => {
      await state('operator_available');
      const old = (await fixture('receipt')).status.control.id;
      await submit(
        page.locator(
          'form[action="/super_admin/instagram_automation/reconnect"]'
        )
      );
      check(
        (await fixture('receipt')).status.control.id !== old,
        'retry has a new request identity'
      );
      await state('running');
      await state('succeeded');
      equal(
        (await fixture('receipt')).status.control.state,
        'succeeded',
        'real terminal success from local fixture transition'
      );
      check(
        (
          await page.locator('[data-request-state="succeeded"]').innerText()
        ).includes(t.requests.succeeded.label),
        'local outcome visible'
      );
      equal(
        (await fixture('receipt')).status.session.state,
        'active',
        'real publication has stored session evidence'
      );
      equal(
        (await fixture('receipt')).status.meta_connectivity,
        'unknown',
        'successful control outcome still does not prove remote Meta'
      );
      await screenshot('desktop-succeeded-light');
    }
  );
  await scenario(
    '14 Account toggle OFF and ON persist; existing Instagram channel kept',
    async () => {
      for (const enabled of [false, true]) {
        const response = await page.goto(
          `${base}/super_admin/accounts/${bootstrap.account_id}/edit`
        );
        equal(response.status(), 200, 'real account edit page');
        const checkbox = accountCheckbox();
        equal(
          await checkbox.count(),
          1,
          'native account feature has a single checkbox'
        );
        await checkbox.setChecked(enabled);
        await submit(checkbox.locator('xpath=ancestor::form'));
        const receipt = await fixture('receipt');
        equal(
          receipt.account_enabled,
          enabled,
          `account flag ${enabled ? 'ON' : 'OFF'} persisted`
        );
        check(
          receipt.channel_preserved && receipt.inbox_preserved,
          'existing Instagram channel and inbox preserved'
        );
        await page.goto(
          `${base}/super_admin/accounts/${bootstrap.account_id}/edit`
        );
        equal(await checkbox.isChecked(), enabled, 'checkbox survives reload');
      }
      await accountCheckbox().scrollIntoViewIfNeeded();
      await screenshot('account-toggle-on-desktop');
      const checkbox = accountCheckbox();
      await checkbox.focus();
      check(
        await checkbox.evaluate(input => document.activeElement === input),
        'account feature accepts keyboard focus'
      );
      const target = await checkbox.evaluate(input => {
        const labels = [...input.labels];
        const bounds = [input, ...labels].map(element =>
          element.getBoundingClientRect()
        );
        return {
          labeled: labels.some(label => label.textContent.trim().length > 0),
          has44pxTarget: bounds.some(
            rect => rect.width >= 44 && rect.height >= 44
          ),
        };
      });
      currentCase.touch_target = target;
      check(target.labeled, 'account feature has associated visible label');
      check(
        target.has44pxTarget,
        'account feature or associated label provides 44px touch target'
      );
    }
  );
  await scenario(
    '15 Real account administrator cannot enter SuperAdmin route',
    async () => {
      const response = await browser.newContext();
      try {
        const signin = await response.request.post(`${base}/auth/sign_in`, {
          data: {
            email: bootstrap.account_email,
            password: bootstrap.password,
          },
        });
        equal(
          signin.status(),
          200,
          'real account administrator login endpoint'
        );
        const headers = signin.headers();
        const auth = Object.fromEntries(
          ['access-token', 'client', 'uid'].map(key => [key, headers[key]])
        );
        check(
          Object.values(auth).every(Boolean),
          'Devise user auth returned required headers'
        );
        const denied = await response.request.get(
          `${base}/super_admin/instagram_automation`,
          { headers: { ...auth, accept: 'application/json' } }
        );
        equal(denied.status(), 401, 'account administrator is not SuperAdmin');
      } finally {
        await response.close();
      }
    }
  );
  await scenario('16 English and Portuguese use real catalogs', async () => {
    for (const locale of ['en', 'pt_BR']) {
      const localized = await fixture('locale', { locale });
      await visit();
      equal(
        await page.locator('#page-title').innerText(),
        localized.translations.title,
        `${locale} title from real catalog`
      );
      check(
        !(await page.locator('#instagram-automation').innerText())
          .toLowerCase()
          .includes('translation missing'),
        `${locale} no missing translation`
      );
    }
  });
  await scenario(
    '17 Six real viewport/theme captures, targets, focus and overflow',
    async () => {
      const themeColors = {};
      const failures = [];
      const observe = operation => {
        try {
          operation();
        } catch (error) {
          failures.push(clean(error.message));
        }
      };
      report.visual_measurements = [];
      for (const [label, viewport] of [
        ['desktop', { width: 1440, height: 1000 }],
        ['mobile', { width: 390, height: 844 }],
        ['narrow', { width: 320, height: 844 }],
      ]) {
        await page.setViewportSize(viewport);
        for (const theme of ['light', 'dark']) {
          await visit();
          await page.emulateMedia({ colorScheme: theme });
          await page.evaluate(
            value =>
              document.documentElement.classList.toggle(
                'dark',
                value === 'dark'
              ),
            theme
          );
          await page.evaluate(() => document.fonts.ready);
          const layout = await page
            .locator('#instagram-automation')
            .evaluate(element => ({
              documentOverflow:
                document.documentElement.scrollWidth - window.innerWidth,
              panelOverflow: element.scrollWidth - element.clientWidth,
              color: getComputedStyle(element.querySelector('h2')).color,
              targets: [
                ...element.querySelectorAll(
                  'input[type="text"], input[type="submit"], button'
                ),
              ].map(control => ({
                id: control.id || control.textContent.trim(),
                width: control.getBoundingClientRect().width,
                height: control.getBoundingClientRect().height,
              })),
            }));
          await page.addScriptTag({
            content:
              fs
                .readFileSync(
                  path.join(
                    root,
                    'tests/qa/instagram-testers/visual-helpers.mjs'
                  ),
                  'utf8'
                )
                .replaceAll('export ', '') +
              '\nwindow.instagramAutomationAppearance = computedAppearance;',
          });
          const appearances = await page
            .locator(
              '#instagram-automation label, #instagram-automation input[type="text"], #instagram-automation input[type="submit"], #instagram-automation button:not(:disabled), #instagram-automation h2'
            )
            .evaluateAll(elements =>
              elements.map(element =>
                window.instagramAutomationAppearance(element)
              )
            );
          for (const appearance of appearances)
            observe(() =>
              check(
                appearance.contrast >= MINIMUM_TEXT_CONTRAST,
                `${label}/${theme} text contrast at least 4.5: ${appearance.text}`
              )
            );
          report.visual_measurements.push({
            viewport,
            theme,
            ...layout,
            appearances,
          });
          await screenshot(`${label}-${theme}`);
          observe(() =>
            equal(
              layout.documentOverflow <= 1 && layout.panelOverflow <= 1,
              true,
              `${label}/${theme} no horizontal overflow`
            )
          );
          for (const target of layout.targets)
            observe(() =>
              check(
                target.height >= 44 && target.width >= 44,
                `${label}/${theme} target ${target.id} at least 44px`
              )
            );
          await page
            .locator('#instagram_automation_INSTAGRAM_META_DEVELOPER_APP_ID')
            .focus();
          const focused = await page
            .locator('#instagram_automation_INSTAGRAM_META_DEVELOPER_APP_ID')
            .evaluate(input => document.activeElement === input);
          observe(() =>
            equal(
              focused,
              true,
              `${label}/${theme} field accepts keyboard focus`
            )
          );
          await page.keyboard.press('Tab');
          const focusedID = await page.evaluate(
            () => document.activeElement.id
          );
          observe(() =>
            equal(
              focusedID,
              'instagram_automation_INSTAGRAM_META_BUSINESS_ID',
              `${label}/${theme} sequential keyboard focus`
            )
          );
          const focus = await page
            .locator('#instagram_automation_INSTAGRAM_META_BUSINESS_ID')
            .evaluate(input => {
              const style = getComputedStyle(input);
              return {
                width: parseFloat(style.outlineWidth),
                style: style.outlineStyle,
              };
            });
          observe(() =>
            check(
              focus.width > 0 && focus.style !== 'none',
              `${label}/${theme} keyboard focus visibly outlined`
            )
          );
          const overlays = await page.locator('vite-error-overlay').count();
          observe(() =>
            equal(overlays, 0, `${label}/${theme} no Vite error overlay`)
          );
          if (label !== 'desktop') {
            await reconnectButton().scrollIntoViewIfNeeded();
            check(
              await reconnectButton().isVisible(),
              'mobile reconnection control visible before PNG'
            );
            await screenshot(`${label}-${theme}-session`);
          }
          if (label === 'desktop') themeColors[theme] = layout.color;
        }
      }
      observe(() =>
        check(
          themeColors.light !== themeColors.dark,
          'supported dark mode changes rendered text color'
        )
      );
      currentCase.failed_checks = failures;
      assert.equal(failures.length, 0, failures.join('\n'));
    }
  );
  await scenario(
    '18 Safety receipts, no browser console failures, unchanged product sources',
    async () => {
      const receipt = await fixture('receipt');
      equal(receipt.smtp_deliveries, 0, 'SMTP delivers nothing');
      check(
        receipt.remote_requests.every(host => host === 'graph.instagram.com'),
        'only synthetic channel subscription Meta fixture attempted'
      );
      check(
        receipt.channel_preserved && receipt.inbox_preserved,
        'synthetic channel unchanged throughout test'
      );
      equal(
        expected422Events,
        1,
        'exactly one expected HTML 422 console diagnostic'
      );
      equal(report.console, [], 'no JS errors or blocked remote browser calls');
      for (const [relative, sourceHash] of Object.entries(report.source_hashes))
        equal(hash(relative), sourceHash, `${relative} unchanged during run`);
      report.final_receipt = {
        ...receipt,
        jobs: receipt.jobs,
        remote_requests: receipt.remote_requests,
      };
    }
  );
} catch (error) {
  report.blocker = clean(error.message);
} finally {
  if (context) await context.close();
  if (browser) await browser.close();
  if (server && server.exitCode === null) {
    server.kill('SIGTERM');
    const deadline = Date.now() + 5000;
    while (
      server.exitCode === null &&
      server.signalCode === null &&
      Date.now() < deadline
    )
      await pause(100);
    if (server.exitCode === null && server.signalCode === null)
      server.kill('SIGKILL');
  }
  report.finished_at = new Date().toISOString();
  const passed = report.cases.filter(entry => entry.status === 'passed').length;
  const failed = report.cases.filter(entry => entry.status === 'failed').length;
  report.counts = {
    executed: report.cases.length,
    passed,
    failed,
    assertions_verified: report.cases.reduce(
      (sum, entry) => sum + entry.checks.length,
      0
    ),
  };
  fs.writeFileSync(
    path.join(output, 'results.json'),
    JSON.stringify(report, null, 2)
  );
  let executionStatus = 'executed';
  if (failed) executionStatus = 'failed';
  if (report.blocker) executionStatus = 'blocked';
  fs.writeFileSync(
    statusFile,
    `${executionStatus.toUpperCase()}\n\n${instructions}\n\nCasos executados: ${report.cases.length}; passaram: ${passed}; falharam: ${failed}. Asserções efetivamente verificadas: ${report.counts.assertions_verified}.\n${report.blocker ? `\nBloqueio: ${report.blocker}\n` : ''}\nEvidência: results.json e screenshots PNG neste diretório. Log privado: server.private.log (não publicar). Nenhum HAR, token ou trace de protocolo gerado.\n`
  );
  console.log(
    JSON.stringify({
      status: executionStatus,
      ...report.counts,
      blocker: report.blocker,
    })
  );
  if (report.blocker || failed) process.exitCode = 1;
}
