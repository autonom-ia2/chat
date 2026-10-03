import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../playwright/node_modules/playwright/index.mjs';
import { origin, output, startServer } from './server.mjs';

const results = {
  startedAt: new Date().toISOString(),
  scope:
    'Real Login.vue, auth client and built dashboard CSS from the checked-out SHA; synthetic API/Auth/dashboard targets; loopback-only Chromium; not real Auth E2E',
  checks: [],
  scenarios: [],
  screenshots: [],
  traces: [],
  blockedExternal: [],
};
let browser;
let server;

const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const safeName = value => value.replace(/[^a-z0-9-]/gi, '-').toLowerCase();
const successResponse = {
  status: 200,
  contentType: 'application/json',
  headers: {
    'access-token': 'synthetic-response-token',
    client: 'synthetic-client',
    expiry: String(Math.floor(Date.now() / 1000) + 3600),
    uid: 'synthetic@example.test',
  },
  body: JSON.stringify({
    data: {
      id: 77,
      account_id: 7,
      accounts: [{ id: 7, name: 'Synthetic QA' }],
    },
  }),
};

async function save() {
  results.finishedAt = new Date().toISOString();
  results.status = results.fatal
    ? 'BLOCKED'
    : results.checks.some(check => check.status === 'FAIL')
      ? 'NEEDS_FIXES'
      : 'PASS';
  results.counts = {
    passed: results.checks.filter(check => check.status === 'PASS').length,
    failed: results.checks.filter(check => check.status === 'FAIL').length,
    screenshots: results.screenshots.length,
    traces: results.traces.length,
  };
  await mkdir(output, { recursive: true });
  await writeFile(
    resolve(output, 'results.json'),
    JSON.stringify(results, null, 2)
  );
}

async function check(name, action) {
  try {
    const evidence = await action();
    results.checks.push({ name, status: 'PASS', evidence });
    console.log(`PASS ${name}`);
  } catch (error) {
    results.checks.push({ name, status: 'FAIL', error: error.message });
    console.log(`FAIL ${name}: ${error.message}`);
  }
}

async function runScenario(name, options, action) {
  const context = await browser.newContext({
    viewport: options.viewport || { width: 1280, height: 900 },
    locale: (options.locale || 'pt_BR').replace('_', '-'),
    timezoneId: 'America/Sao_Paulo',
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  const record = {
    name,
    apiAttempts: 0,
    authNavigations: 0,
    consoleErrors: [],
    pageErrors: [],
    requestFailures: [],
  };
  results.scenarios.push(record);
  page.on('console', message => {
    if (message.type() === 'error') record.consoleErrors.push(message.text());
  });
  page.on('pageerror', error => record.pageErrors.push(error.message));
  page.on('requestfailed', request => {
    record.requestFailures.push({
      url: request.url(),
      error: request.failure()?.errorText,
    });
  });
  await context.tracing.start({
    screenshots: true,
    snapshots: true,
    sources: true,
  });
  await context.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.hostname !== '127.0.0.1' || url.port !== '3438') {
      results.blockedExternal.push({ scenario: name, url: url.href });
      return route.abort('blockedbyclient');
    }
    if (url.pathname === '/auth/autonomia') record.authNavigations += 1;
    if (url.pathname !== '/auth/sign_in') return route.continue();

    record.apiAttempts += 1;
    const response =
      typeof options.api === 'function'
        ? options.api(record.apiAttempts)
        : options.api;
    if (response === 'network-error') return route.abort('connectionfailed');
    return route.fulfill(response || successResponse);
  });

  const trace = resolve(output, `${safeName(name)}-trace.zip`);
  try {
    const query = new URLSearchParams({
      locale: options.locale || 'pt_BR',
      scenario: name,
    });
    if (options.redirectTo) query.set('redirect_to', options.redirectTo);
    if (options.configuredAuthUrl) {
      query.set('configured_auth_url', options.configuredAuthUrl);
    }
    await page.goto(`${origin}/app/login?${query}`);
    await action({ context, page, record });
    assert(
      record.pageErrors.length === 0,
      `Page errors: ${record.pageErrors.join('; ')}`
    );
  } finally {
    await context.tracing.stop({ path: trace });
    results.traces.push(trace.replace(`${output}/`, ''));
    await context.close();
  }
  return record;
}

async function screenshot(page, name) {
  await page.evaluate(() => document.fonts.ready);
  const path = resolve(output, `${safeName(name)}.png`);
  await page.screenshot({ path, fullPage: true });
  results.screenshots.push(path.replace(`${output}/`, ''));
  return path;
}

const jsonError = status => ({
  status,
  contentType: 'application/json',
  body: JSON.stringify({ error: 'Synthetic authentication failure' }),
});

try {
  await mkdir(output, { recursive: true });
  ({ server } = await startServer());
  browser = await chromium.launch({ headless: true });

  await check(
    '422 validation failure stops loading and returns once to trusted Auth',
    async () => {
      const record = await runScenario(
        'terminal-422-safe-return',
        {
          api: jsonError(422),
          redirectTo: '/app/accounts/7/dashboard?conversation=2',
        },
        async ({ page, record: scenario }) => {
          await page.getByTestId('synthetic-auth-login').waitFor();
          await page.waitForTimeout(500);
          const url = new URL(page.url());
          assert(url.origin === origin, `Unexpected origin: ${url.origin}`);
          assert(
            url.pathname === '/auth/autonomia',
            `Unexpected path: ${url.pathname}`
          );
          assert(
            url.searchParams.get('prompt') === 'login',
            'Missing prompt=login'
          );
          assert(
            url.searchParams.get('return_to') ===
              '/app/accounts/7/dashboard?conversation=2',
            `Safe return_to not preserved: ${url.search}`
          );
          assert(
            !url.href.includes('synthetic-one-time-token'),
            'SSO token leaked into redirect'
          );
          assert(!url.searchParams.has('email'), 'Email leaked into redirect');
          assert(
            scenario.apiAttempts === 1,
            `Expected one API attempt, got ${scenario.apiAttempts}`
          );
          assert(
            scenario.authNavigations === 1,
            `Expected one Auth navigation, got ${scenario.authNavigations}`
          );
          await screenshot(page, 'terminal-422-auth-return');
        }
      );
      return {
        apiAttempts: record.apiAttempts,
        authNavigations: record.authNavigations,
      };
    }
  );

  for (const status of [401, 410]) {
    await check(
      `${status} invalid or expired token returns to Auth without a loop`,
      async () => {
        const record = await runScenario(
          `terminal-${status}`,
          { api: jsonError(status) },
          async ({ page, record: scenario }) => {
            await page.getByTestId('synthetic-auth-login').waitFor();
            await page.waitForTimeout(500);
            assert(
              scenario.apiAttempts === 1,
              `Expected one API attempt, got ${scenario.apiAttempts}`
            );
            assert(
              scenario.authNavigations === 1,
              `Expected one Auth navigation, got ${scenario.authNavigations}`
            );
            assert(
              new URL(page.url()).searchParams.get('prompt') === 'login',
              'Missing prompt=login'
            );
          }
        );
        return {
          status,
          apiAttempts: record.apiAttempts,
          authNavigations: record.authNavigations,
        };
      }
    );
  }

  await check(
    '503 stops loading and presents retry/restart actions',
    async () => {
      await runScenario(
        'transient-503-desktop',
        { api: jsonError(503) },
        async ({ page, record }) => {
          const error = page.getByTestId('autonomia_sso_error');
          await error.waitFor();
          await page.getByTestId('autonomia_sso_retry').waitFor();
          assert(
            record.apiAttempts === 1,
            `Expected one API attempt, got ${record.apiAttempts}`
          );
          assert(
            record.authNavigations === 0,
            'Transient failure redirected automatically'
          );
          assert(
            (await error.innerText()).trim().length > 20,
            'Transient state has no useful message'
          );
          await screenshot(page, 'transient-503-desktop');
        }
      );
      return 'Visible transient state captured in pt_BR';
    }
  );

  await check(
    'network failure stops loading on a mobile viewport',
    async () => {
      await runScenario(
        'network-error-mobile',
        {
          api: 'network-error',
          locale: 'en',
          viewport: { width: 390, height: 844 },
        },
        async ({ page, record }) => {
          await page.getByTestId('autonomia_sso_error').waitFor();
          assert(
            record.apiAttempts === 1,
            `Expected one API attempt, got ${record.apiAttempts}`
          );
          assert(
            record.authNavigations === 0,
            'Network failure redirected automatically'
          );
          await screenshot(page, 'network-error-mobile');
        }
      );
      return 'Visible transient state captured in en at 390x844';
    }
  );

  await check(
    'retry clears the error and preserves the existing success redirect',
    async () => {
      const record = await runScenario(
        'retry-then-success',
        {
          api: attempt => (attempt === 1 ? jsonError(503) : successResponse),
          redirectTo: '/app/accounts/7/dashboard',
        },
        async ({ page, record: scenario }) => {
          await page.getByTestId('autonomia_sso_error').waitFor();
          await screenshot(page, 'retry-before-success');
          await page.getByTestId('autonomia_sso_retry').click();
          await page.getByTestId('synthetic-chatwoot-success').waitFor();
          assert(
            scenario.apiAttempts === 2,
            `Expected two API attempts, got ${scenario.apiAttempts}`
          );
          assert(
            new URL(page.url()).pathname === '/app/accounts/7/dashboard',
            `Unexpected success URL: ${page.url()}`
          );
          await screenshot(page, 'retry-success');
        }
      );
      return { apiAttempts: record.apiAttempts };
    }
  );

  await check(
    'unsafe configured Auth URL and external return_to are discarded',
    async () => {
      const record = await runScenario(
        'unsafe-redirects',
        {
          api: jsonError(403),
          redirectTo: 'https://attacker.invalid/collect',
          configuredAuthUrl: 'https://attacker.invalid/login?token=bad',
        },
        async ({ page, record: scenario }) => {
          await page.getByTestId('synthetic-auth-login').waitFor();
          const url = new URL(page.url());
          assert(url.origin === origin, `Open redirect attempted: ${url.href}`);
          assert(
            url.pathname === '/auth/autonomia',
            `Unexpected path: ${url.pathname}`
          );
          assert(
            !url.searchParams.has('return_to'),
            `Unsafe return_to preserved: ${url.search}`
          );
          assert(
            !url.searchParams.has('token'),
            `Configured token leaked: ${url.search}`
          );
          assert(
            scenario.apiAttempts === 1,
            `Expected one API attempt, got ${scenario.apiAttempts}`
          );
          assert(
            scenario.authNavigations === 1,
            `Expected one Auth navigation, got ${scenario.authNavigations}`
          );
          await screenshot(page, 'unsafe-redirects-discarded');
        }
      );
      return {
        apiAttempts: record.apiAttempts,
        authNavigations: record.authNavigations,
      };
    }
  );

  await check(
    'artifact summary contains no real credentials or external requests',
    async () => {
      assert(
        results.blockedExternal.length === 0,
        `External requests attempted: ${JSON.stringify(results.blockedExternal)}`
      );
      const source = await readFile(new URL(import.meta.url), 'utf8');
      assert(
        !/AKIA[0-9A-Z]{16}/.test(source),
        'AWS-shaped credential found in harness'
      );
      return 'Only documented synthetic values are used; browser observed loopback traffic only';
    }
  );
} catch (error) {
  results.fatal = error.stack || error.message;
  console.error(error);
} finally {
  if (browser) await browser.close();
  if (server) await server.close();
  await save();
}

if (results.status !== 'PASS') process.exitCode = 1;
