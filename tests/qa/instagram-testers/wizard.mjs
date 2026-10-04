/* eslint-disable no-await-in-loop, no-restricted-syntax -- Screens are captured sequentially to keep each synthetic state isolated. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys, @intlify/vue-i18n/no-missing-keys -- Harness reads real locale catalogs via browser helper and checks missing keys at runtime. */
import assert from 'node:assert/strict';
import { mkdir, stat, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServer, root, output, origin } from './server.mjs';
import {
  sourceFingerprints,
  styleFingerprints,
  dependencyMap,
  observeStyles,
  consumedStyleFingerprints,
  captureUsedStyleSheets,
} from './evidence.mjs';
import {
  candidates,
  errorResponse,
  json,
  responseFor,
  deferred,
} from './fixtures.mjs';

const screenshotRoot = resolve(output, 'wizard');
let build;

const views = [
  { name: 'desktop', viewport: { width: 1440, height: 900 } },
  { name: 'mobile', viewport: { width: 390, height: 844 } },
];
const themes = ['light', 'dark'];
const results = {
  startedAt: new Date().toISOString(),
  scope:
    'Telas reais do wizard de inbox e do fluxo Instagram com flag ligada/desligada; API interna simulada em loopback; Meta/OAuth/proxy externos bloqueados.',
  evidence: [],
  screenshots: [],
  blockedExternal: [],
  limits: [
    'A API de busca, convite, status e configuração é sintética e não comprova homologação Meta.',
    'A reautorização exerce clique e POST interno sem seleção; a navegação OAuth externa é abortada antes da rede.',
    'Canais, Instagram, agentes, conclusão e reautorização usam contextos e estados sintéticos separados: nenhuma jornada fim a fim é comprovada.',
    'A atribuição de agente é capturada antes do PATCH para preservar a execução local sem mutação persistente.',
  ],
};

const tick = () =>
  new Promise(done => {
    setTimeout(done, 25);
  });
async function until(predicate, message) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await tick();
  }
  throw new Error(message);
}

function stagePath(stage) {
  return {
    channels: '/app/accounts/910/settings/inboxes/new',
    instagram: '/app/accounts/910/settings/inboxes/new/instagram',
    agents: '/app/accounts/910/settings/inboxes/new/9101/agents',
    finish: '/app/accounts/910/settings/inboxes/new/9101/finish',
  }[stage];
}

async function openCase(id, options, browser) {
  const context = await browser.newContext({
    viewport: options.viewport,
    colorScheme: options.theme,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const state = { ...options.state, restricted: Boolean(options.restricted) };
  const record = {
    id,
    viewport: options.viewport,
    theme: options.theme,
    requests: [],
    pageErrors: [],
    consoleErrors: [],
    transportDiagnostics: [],
    routeErrors: [],
    screenshots: [],
  };
  results.evidence.push(record);
  const verifyConsumedStyles = observeStyles(page, record, origin, build);
  page.on('pageerror', error => record.pageErrors.push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const locationPath = new URL(message.location().url || origin, origin)
      .pathname;
    const expected = record.requests.some(
      request =>
        request.path === locationPath &&
        request.responseStatus >= 400 &&
        message
          .text()
          .startsWith(
            'Failed to load resource: the server responded with a status of '
          )
    );
    if (expected) record.transportDiagnostics.push(message.text());
    else record.consoleErrors.push(message.text());
  });
  await context.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin !== origin) {
      const blocked = {
        case: id,
        origin: url.origin,
        path: url.pathname,
        resourceType: request.resourceType(),
      };
      results.blockedExternal.push(blocked);
      await route.abort('blockedbyclient');
      return;
    }
    if (!url.pathname.startsWith('/api/')) {
      await route.continue();
      return;
    }
    const item = {
      method: request.method(),
      path: url.pathname,
      contractValidated: false,
    };
    record.requests.push(item);
    try {
      const raw = request.postData();
      const response = await responseFor(
        url,
        request.method(),
        raw ? JSON.parse(raw) : null,
        state
      );
      item.contractValidated = true;
      item.responseStatus = response.status;
      await route.fulfill(response);
    } catch (error) {
      record.routeErrors.push(error.message);
      await route.abort().catch(() => {});
    }
  });
  const flow = options.flow || 'wizard';
  const path =
    flow === 'reauthorize'
      ? '/app/accounts/910/settings/inboxes/new/reauthorize'
      : stagePath(options.stage);
  const query = new URLSearchParams({
    flow,
    stage: options.stage || '',
    feature: options.feature || 'on',
    locale: 'pt_BR',
    theme: options.theme,
    restricted: String(options.restricted || false),
    ...options.query,
  });
  await page.goto(`${origin}${path}?${query}`, {
    waitUntil: 'domcontentloaded',
  });
  await page.waitForFunction(() => window.instagramQa?.ready === true, null, {
    timeout: 120000,
  });
  await page.evaluate(() => document.fonts.ready);
  if (await page.locator('section').count()) {
    await until(
      async () =>
        (await page.locator('section').getAttribute('aria-busy')) === 'false',
      'Instagram screen did not settle'
    );
  }

  async function health() {
    await verifyConsumedStyles();
    record.styleSheetsConsumed = await captureUsedStyleSheets(page);
    const data = await page.evaluate(() => {
      const app = document.querySelector('#app');
      return {
        text: app?.innerText || '',
        overlay: Boolean(document.querySelector('vite-error-overlay')),
        stylesheets: [
          ...document.querySelectorAll('link[rel="stylesheet"]'),
        ].map(link => ({
          path: new URL(link.href).pathname,
          loaded: Boolean(link.sheet),
        })),
        missing: window.instagramQa.missing,
        vueErrors: window.instagramQa.vueErrors,
        vueWarnings: window.instagramQa.vueWarnings,
        viewport: { width: window.innerWidth, height: window.innerHeight },
        documentWidth: document.documentElement.scrollWidth,
        controls: [...app.querySelectorAll('button, input, a')]
          .filter(element => element.getBoundingClientRect().height > 0)
          .map(element => {
            const rect = element.getBoundingClientRect();
            return {
              tag: element.tagName,
              text: element.textContent.trim(),
              width: rect.width,
              height: rect.height,
              scrollWidth: element.scrollWidth,
              clientWidth: element.clientWidth,
            };
          }),
      };
    });
    record.latestHealth = data;
    assert.ok(data.text.length > 20, 'Tela real vazia');
    assert.equal(data.overlay, false, 'Vite error overlay');
    for (const stylesheetPath of [build.css, build.utilities])
      assert.ok(
        data.stylesheets.some(
          sheet => sheet.path === stylesheetPath && sheet.loaded
        ),
        `CSS ausente: ${stylesheetPath}`
      );
    assert.deepEqual(data.missing, [], 'Chaves i18n ausentes');
    assert.deepEqual(data.vueErrors, [], 'Erro Vue');
    assert.deepEqual(data.vueWarnings, [], 'Aviso Vue');
    assert.deepEqual(record.pageErrors, [], 'Erro de página');
    assert.deepEqual(record.consoleErrors, [], 'Erro de console');
    assert.deepEqual(record.routeErrors, [], 'Contrato interno inesperado');
    assert.ok(
      data.documentWidth <= data.viewport.width + 1,
      `Overflow horizontal ${data.documentWidth} > ${data.viewport.width}`
    );
    for (const control of data.controls) {
      if (options.flow === 'wizard' || options.flow === 'reauthorize') {
        record.targetDiagnostics = data.controls;
        break;
      }
      assert.ok(
        control.width >= 44 && control.height >= 44,
        `Alvo interativo pequeno: ${control.tag} ${control.text} ${control.width}x${control.height}`
      );
      if (control.tag !== 'INPUT') {
        assert.ok(
          control.scrollWidth <= control.clientWidth + 1,
          `Texto cortado: ${control.text}`
        );
      }
    }
    assert.ok(!data.text.includes('QA_UPSTREAM_PRIVATE_MARKER_910'));
    assert.ok(!data.text.includes('synthetic-selection-'));
    return data;
  }

  async function screenshot(label) {
    const data = await health();
    const filename = `${id}-${label}-${options.viewport.name || 'view'}-${options.theme}.png`;
    const pathOnDisk = resolve(screenshotRoot, filename);
    await page.screenshot({
      path: pathOnDisk,
      fullPage: true,
      animations: 'disabled',
      caret: 'hide',
    });
    const item = {
      case: id,
      label,
      file: filename,
      bytes: (await stat(pathOnDisk)).size,
      viewport: options.viewport,
      theme: options.theme,
      capture: 'fullPage em componente real',
      textLength: data.text.length,
    };
    assert.ok(item.bytes > 0, 'Screenshot vazio');
    record.screenshots.push(filename);
    results.screenshots.push(item);
  }

  return {
    page,
    context,
    state,
    record,
    screenshot,
    health,
    async close() {
      for (const key of ['searchGate', 'statusGate', 'inviteGate', 'oauthGate'])
        state[key]?.resolve();
      await context.close();
    },
  };
}

async function t(page, key, values) {
  return page.evaluate(
    ([message, parameters]) => window.instagramQa.t(message, parameters),
    [`INBOX_MGMT.ADD.INSTAGRAM.TESTER.${key}`, values]
  );
}

async function searchTester(q, state) {
  const input = q.page.getByRole('textbox', {
    name: 'Usuário do Instagram',
    exact: true,
  });
  await input.fill('@empresa_sintetica_qa910');
  await input.press('Enter');
  await until(
    () => q.record.requests.some(request => request.path.endsWith('/search')),
    'Busca sintética não iniciou'
  );
  if (!state.searchGate) await q.page.evaluate(() => document.fonts.ready);
  return input;
}

async function waitSearch(q, key) {
  await q.page
    .getByText(await t(q.page, key), { exact: true })
    .first()
    .waitFor({ state: 'visible' });
}

async function selectFirst(q, statusKey) {
  const candidate = (q.state.candidates || candidates)[0];
  await q.page
    .getByRole('button', {
      name: await t(q.page, 'SELECT_PROFILE', candidate),
      exact: true,
    })
    .click();
  await until(
    async () =>
      (await q.page.locator('section').getAttribute('aria-busy')) === 'false',
    'Status sintético não terminou'
  );
  if (statusKey) await waitSearch(q, statusKey);
}

const cases = [
  {
    id: 'wizard-channels',
    flow: 'wizard',
    stage: 'channels',
    action: async q => {
      assert.ok(
        (await q.page.locator('#app').innerText()).includes('Instagram')
      );
      await q.screenshot('choice-instagram');
      await q.page
        .getByRole('button')
        .filter({ has: q.page.getByText('Instagram', { exact: true }) })
        .click();
      await q.page
        .getByRole('textbox', { name: 'Usuário do Instagram', exact: true })
        .waitFor();
      await until(
        () =>
          q.record.requests.some(
            item =>
              item.path.endsWith('/testers/configuration') &&
              item.contractValidated
          ),
        'Configuração não carregou após clique no canal'
      );
    },
  },
  {
    id: 'wizard-instagram-profile',
    flow: 'wizard',
    stage: 'instagram',
    action: async q => q.screenshot('profile'),
  },
  {
    id: 'wizard-instagram-search-loading',
    flow: 'wizard',
    stage: 'instagram',
    state: { searchGate: deferred() },
    action: async q => {
      await searchTester(q, q.state);
      await q.page
        .locator('section[aria-busy="true"]')
        .waitFor({ state: 'visible' });
      await q.screenshot('loading');
      q.state.searchGate.resolve();
      await waitSearch(q, 'RESULTS_TITLE');
    },
  },
  {
    id: 'wizard-instagram-search-empty',
    flow: 'wizard',
    stage: 'instagram',
    state: { search: json({ results: [] }) },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'EMPTY');
      await q.screenshot('empty');
    },
  },
  {
    id: 'wizard-instagram-results',
    flow: 'wizard',
    stage: 'instagram',
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await q.screenshot('results');
    },
  },
  {
    id: 'wizard-instagram-absent',
    flow: 'wizard',
    stage: 'instagram',
    state: { status: 'absent' },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await selectFirst(q, 'ABSENT_TITLE');
      await q.screenshot('absent');
    },
  },
  {
    id: 'wizard-instagram-pending',
    flow: 'wizard',
    stage: 'instagram',
    state: { status: 'pending' },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await selectFirst(q, 'PENDING_TITLE');
      await q.screenshot('pending');
    },
  },
  {
    id: 'wizard-instagram-accepted',
    flow: 'wizard',
    stage: 'instagram',
    state: { status: 'accepted' },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await selectFirst(q, 'CONFIRMED_TITLE');
      await q.screenshot('accepted');
    },
  },
  {
    id: 'wizard-instagram-status-error',
    flow: 'wizard',
    stage: 'instagram',
    state: { statusResponse: errorResponse('unknown_status', 502) },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await selectFirst(q, 'STATUS_ERROR');
      await q.screenshot('status-error');
    },
  },
  {
    id: 'wizard-instagram-config-error',
    flow: 'wizard',
    stage: 'instagram',
    state: { configuration: errorResponse('meta_session_expired') },
    action: async q => {
      await waitSearch(q, 'UNAVAILABLE');
      await q.screenshot('configuration-error');
    },
  },
  {
    id: 'wizard-instagram-restricted',
    flow: 'wizard',
    stage: 'instagram',
    restricted: true,
    action: async q => {
      const target = q.page.getByRole('button', {
        name: await t(q.page, 'SEARCH'),
        exact: true,
      });
      assert.ok(await target.isDisabled());
      await q.page
        .getByRole('textbox', { name: 'Usuário do Instagram', exact: true })
        .fill('@empresa_sintetica_qa910');
      await q.page
        .getByRole('textbox', { name: 'Usuário do Instagram', exact: true })
        .press('Enter');
      await q.health();
      assert.equal(
        q.record.requests.filter(item => !item.path.endsWith('/configuration'))
          .length,
        0
      );
      await q.screenshot('restricted');
    },
  },
  {
    id: 'wizard-instagram-proxy-search-error',
    flow: 'wizard',
    stage: 'instagram',
    state: { search: errorResponse('proxy_unavailable') },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'UNAVAILABLE');
      await q.screenshot('proxy-unavailable');
    },
  },
  {
    id: 'wizard-instagram-proxy-status-error',
    flow: 'wizard',
    stage: 'instagram',
    state: { statusResponse: errorResponse('proxy_unavailable') },
    action: async q => {
      await searchTester(q, q.state);
      await waitSearch(q, 'RESULTS_TITLE');
      await selectFirst(q, 'UNAVAILABLE');
      await q.screenshot('proxy-unavailable');
    },
  },
  {
    id: 'wizard-instagram-plan-limit',
    flow: 'wizard',
    stage: 'instagram',
    query: {
      error_type: 'LimitExceeded',
      code: '402',
      error_message: 'QA_UPSTREAM_PRIVATE_MARKER_910',
    },
    action: async q => {
      const copy = await q.page.evaluate(() =>
        window.instagramQa.t('INBOX_MGMT.ADD.INSTAGRAM.ERROR_INBOX_LIMIT')
      );
      await q.page.getByText(copy, { exact: true }).first().waitFor();
      assert.equal(
        q.record.requests.some(item => item.path.endsWith('/authorization')),
        false
      );
      await q.screenshot('plan-limit');
    },
  },
  {
    id: 'wizard-instagram-legacy-feature-off',
    flow: 'wizard',
    stage: 'instagram',
    feature: 'off',
    state: { legacy: true },
    action: async q => {
      assert.equal(
        q.record.requests.length,
        0,
        'Feature-off fez request antes do CTA legado'
      );
      assert.equal(
        await q.page
          .getByRole('button', {
            name: await q.page.evaluate(() =>
              window.instagramQa.t(
                'INBOX_MGMT.ADD.INSTAGRAM.CONTINUE_WITH_INSTAGRAM'
              )
            ),
            exact: true,
          })
          .count(),
        1,
        'CTA OAuth legado não está visível'
      );
      assert.equal(
        q.record.requests.some(request => request.path.includes('/testers')),
        false,
        'Feature-off chamou a API nova de testers'
      );
      await q.screenshot('legacy-feature-off');
    },
  },
  {
    id: 'wizard-agents',
    flow: 'wizard',
    stage: 'agents',
    action: async q => {
      await q.screenshot('agent-list');
      await q.page.getByTestId('agent-selector').click();
      await q.page.getByRole('button', { name: 'Ana QA', exact: true }).click();
      const stageTitle = await q.page.evaluate(() =>
        window.instagramQa.t('INBOX_MGMT.ADD.AGENTS.TITLE')
      );
      await q.page
        .getByRole('heading', { name: stageTitle, level: 2, exact: true })
        .click();
      await q.page
        .getByRole('button', { name: 'Bruno QA', exact: true })
        .waitFor({ state: 'hidden' });
      await q.page
        .getByTestId('agent-selector')
        .getByText('Ana QA', { exact: true })
        .waitFor({ state: 'visible' });
      assert.equal(
        q.record.requests.length,
        0,
        'Closing agent menu persisted a mutation'
      );
      q.record.agentSelection = {
        selected: 'Ana QA',
        dropdownClosed: true,
        mutationRequests: 0,
      };
      await q.screenshot('agent-selected');
    },
  },
  {
    id: 'wizard-finish',
    flow: 'wizard',
    stage: 'finish',
    action: async q => q.screenshot('finish'),
  },
  {
    id: 'instagram-reauthorize',
    flow: 'reauthorize',
    stage: 'reauthorize',
    state: { reauthorize: true, oauthGate: deferred() },
    action: async q => {
      assert.ok(
        (await q.page.locator('#app').innerText())
          .toLowerCase()
          .includes('reconectar')
      );
      await q.screenshot('reauthorize');
      assert.equal(q.record.requests.length, 0);
      const authorizationPath = '/api/v1/accounts/910/instagram/authorization';
      const requested = q.page.waitForRequest(request => {
        if (
          new URL(request.url()).pathname !== authorizationPath ||
          request.method() !== 'POST'
        )
          return false;
        const raw = request.postData();
        assert.deepEqual(
          raw ? JSON.parse(raw) : null,
          { inbox_id: 9101, return_to: 'inbox' },
          'Reautorização exige a caixa existente e destino inbox, sem seleção'
        );
        return true;
      });
      const label = await q.page.evaluate(() =>
        window.instagramQa.t('INBOX_MGMT.CLICK_TO_RECONNECT')
      );
      await q.page.getByRole('button', { name: label, exact: true }).click();
      await requested;
      await q.health();
      q.state.oauthGate.resolve();
      await until(
        () =>
          q.record.requests.some(
            item =>
              item.path === authorizationPath &&
              item.method === 'POST' &&
              item.contractValidated &&
              item.responseStatus === 200
          ),
        'Contrato POST de reautorização não terminou'
      );
      await until(
        () =>
          results.blockedExternal.some(
            item =>
              item.case === q.record.id &&
              item.origin === 'https://www.instagram.com' &&
              item.path === '/qa-synthetic-oauth-910'
          ),
        'OAuth externo não foi abortado'
      );
      q.record.reauthorizeClick = {
        method: 'POST',
        path: authorizationPath,
        bodyKeys: ['inbox_id', 'return_to'],
        responseStatus: 200,
        externalNavigation: 'blocked',
      };
      q.record.expectedBlockedOAuthNavigation = true;
    },
  },
];

let browser;
let server;
try {
  await mkdir(screenshotRoot, { recursive: true });
  results.sourceHashes = await sourceFingerprints(root);
  results.sourceHashesBefore = results.sourceHashes;
  const modulePath = process.env.PLAYWRIGHT_MODULE_PATH;
  if (!modulePath)
    throw new Error(
      'PLAYWRIGHT_MODULE_PATH ausente; nenhuma instalação será baixada'
    );
  const entry = modulePath.endsWith('.mjs')
    ? modulePath
    : resolve(modulePath, 'index.mjs');
  const { chromium } = await import(pathToFileURL(entry).href);
  build = await startServer();
  server = build.server;
  results.styles = { dashboard: build.css, utilities: build.utilities };
  results.styleHashesBefore = await styleFingerprints(root, build);
  browser = await chromium.launch({
    headless: true,
    ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
      ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
      : {}),
  });
  results.browser = {
    name: 'Chromium isolado',
    version: browser.version(),
    externalNetwork: 'blocked',
  };
  for (const definition of cases) {
    for (const view of views) {
      for (const theme of themes) {
        const viewOptions = { ...view, name: view.name };
        const state = Object.fromEntries(
          Object.entries(definition.state || {}).map(([key, value]) => [
            key,
            value && value.promise && typeof value.resolve === 'function'
              ? deferred()
              : value,
          ])
        );
        const id = `${definition.id}-${view.name}-${theme}`;
        let q;
        try {
          q = await openCase(
            id,
            { ...definition, ...viewOptions, theme, state },
            browser
          );
          await definition.action(q);
          if (!q.record.expectedBlockedOAuthNavigation) await q.health();
          results.evidence.find(item => item.id === id).status = 'PASS';
          process.stdout.write(`PASS ${id}\n`);
        } catch (error) {
          const evidence = results.evidence.find(item => item.id === id);
          if (evidence) {
            evidence.status = 'FAIL';
            evidence.error = error.message;
          }
          results.failed = (results.failed || 0) + 1;
          process.stdout.write(`FAIL ${id}: ${error.message}\n`);
        } finally {
          await q?.close();
        }
      }
    }
  }
  results.dependencyMap = await dependencyMap(
    root,
    server,
    results.sourceHashesBefore,
    build.physicalRoots
  );
  results.stylesConsumedHashes = consumedStyleFingerprints(
    results.evidence,
    build
  );
  results.styleHashesAfter = await styleFingerprints(root, build);
  assert.deepEqual(
    results.styleHashesAfter,
    results.styleHashesBefore,
    'CSS mudou durante captura'
  );
  results.sourceHashesAfter = await sourceFingerprints(root);
  assert.deepEqual(
    results.sourceHashesAfter,
    results.sourceHashesBefore,
    'Código mudou durante a captura; repetir contra checkout estável'
  );
} catch (error) {
  results.fatal = error.message;
  process.stderr.write(`BLOCKED ${error.message}\n`);
} finally {
  await browser?.close();
  await server?.close();
  results.finishedAt = new Date().toISOString();
  results.counts = {
    pass: results.evidence.filter(item => item.status === 'PASS').length,
    fail: results.evidence.filter(item => item.status === 'FAIL').length,
    screenshots: results.screenshots.length,
  };
  results.counts.blocked =
    cases.length * views.length * themes.length - results.evidence.length;
  results.status = 'PASS';
  if (results.counts.fail) results.status = 'FAIL';
  if (results.fatal || results.counts.blocked) results.status = 'BLOCKED';
  await mkdir(screenshotRoot, { recursive: true });
  await writeFile(
    resolve(screenshotRoot, 'results.json'),
    JSON.stringify(results, null, 2)
  );
  process.stdout.write(
    `${JSON.stringify({ status: results.status, ...results.counts })}\n`
  );
  if (results.status !== 'PASS') process.exitCode = 1;
}
