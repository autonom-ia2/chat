/* eslint-disable no-await-in-loop, no-restricted-syntax -- Browser actions and isolated cases intentionally run sequentially. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys, @intlify/vue-i18n/no-missing-keys -- Harness reads real locale catalogs via browser helper and checks missing keys at runtime. */
import assert from 'node:assert/strict';
import { mkdir, stat, writeFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServer, root, output, origin, pathname } from './server.mjs';
import {
  sourceFingerprints,
  styleFingerprints,
  dependencyMap,
  observeStyles,
  consumedStyleFingerprints,
  captureUsedStyleSheets,
} from './evidence.mjs';
import {
  MINIMUM_TEXT_CONTRAST,
  primaryButtonCoverage,
} from './visual-helpers.mjs';
import { assertToastEvidence, readToastEvidence } from './toast-helpers.mjs';
import {
  acceptanceUrl,
  appName,
  candidates,
  longCandidate,
  configuration,
  json,
  errorResponse,
  deferred,
  responseFor,
} from './fixtures.mjs';

const results = {
  startedAt: new Date().toISOString(),
  scope:
    'Actual Instagram.vue and real children; repository dashboard CSS and current Tailwind utilities; synthetic internal HTTP. Component browser QA, not backend E2E or real Meta/OAuth acceptance. No wizard/sidebar shell.',
  cases: [],
  screenshots: [],
  screens: [],
  blockedExternal: [],
  limits: [
    'Backend permissions, locking, Meta session/parser and OAuth callback are not exercised here.',
    'CSS zoom 200% is reflow emulation, not browser toolbar zoom.',
    'Screenshots require independent visual review; automated geometry does not prove aesthetic acceptance.',
  ],
};
let browser;
let server;
let build;
const definitions = [];
const fingerprints = () => sourceFingerprints(root);
const define = (id, options, action) =>
  definitions.push({ id, options, action });
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

async function openScreen(id, options) {
  const viewport = options.viewport || { width: 1440, height: 900 };
  const locale = options.locale || 'pt_BR';
  const theme = options.theme || 'light';
  const context = await browser.newContext({
    viewport,
    locale: locale.replace('_', '-'),
    colorScheme: theme,
    timezoneId: 'America/Sao_Paulo',
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const state = { ...options.state, restricted: Boolean(options.restricted) };
  const record = {
    id,
    viewport,
    locale,
    theme,
    zoom: options.zoom || 1,
    requests: [],
    consoleErrors: [],
    transportDiagnostics: [],
    pageErrors: [],
    routeErrors: [],
    expectedToast: '',
    screenshots: [],
    visualChecks: [],
  };
  results.screens.push(record);
  const verifyConsumedStyles = observeStyles(page, record, origin, build);
  page.on('pageerror', error => record.pageErrors.push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const location = message.location();
    const requestPath = new URL(location.url || origin, origin).pathname;
    const expected = record.requests.some(
      request => request.path === requestPath && request.responseStatus >= 400
    );
    const expectedTimeout =
      record.requests.some(
        request =>
          request.path === requestPath &&
          request.transportFailure === 'timedout'
      ) && message.text() === 'Failed to load resource: net::ERR_TIMED_OUT';
    if (
      expectedTimeout ||
      (expected &&
        message
          .text()
          .startsWith(
            'Failed to load resource: the server responded with a status of '
          ))
    )
      record.transportDiagnostics.push({
        text: message.text(),
        path: new URL(location.url, origin).pathname,
      });
    else record.consoleErrors.push(message.text());
  });
  const blocked = [];
  await context.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin !== origin) {
      const item = {
        screen: id,
        origin: url.origin,
        path: url.pathname,
        resourceType: request.resourceType(),
      };
      results.blockedExternal.push(item);
      blocked.push(item);
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
      if (
        state.authorizationTimeout &&
        url.pathname === '/api/v1/accounts/910/instagram/authorization'
      ) {
        assert.equal(state.legacy, true, 'Timeout injection is legacy-only');
        item.transportFailure = 'timedout';
        await route.abort('timedout');
        return;
      }
      item.responseStatus = response.status;
      await route.fulfill(response);
    } catch (error) {
      if (!page.isClosed()) record.routeErrors.push(error.message);
      await route.abort().catch(() => {});
    }
  });
  const query = new URLSearchParams({
    locale,
    theme,
    feature: options.feature || 'on',
    restricted: String(options.restricted || false),
    ...options.query,
  });
  await page.goto(`${origin}${pathname}?${query}`, {
    waitUntil: 'domcontentloaded',
  });
  await page.waitForFunction(() => window.instagramQa?.ready === true, null, {
    timeout: 60000,
  });
  if (options.zoom)
    await page.evaluate(zoom => {
      document.documentElement.style.zoom = String(zoom);
    }, options.zoom);
  const section = page.locator('section');
  async function settle() {
    if (await section.count())
      await until(
        async () => (await section.getAttribute('aria-busy')) === 'false',
        'Component action did not finish'
      );
    await page.evaluate(() => document.fonts.ready);
  }
  await settle();
  const t = (key, values) =>
    page.evaluate(
      ([message, parameters]) => window.instagramQa.t(message, parameters),
      [`INBOX_MGMT.ADD.INSTAGRAM.TESTER.${key}`, values]
    );
  const button = async key =>
    page.getByRole('button', { name: await t(key), exact: true });
  const continueButton = async () =>
    page.getByRole('button', {
      name: await page.evaluate(() =>
        window.instagramQa.t('INBOX_MGMT.ADD.INSTAGRAM.CONTINUE_WITH_INSTAGRAM')
      ),
      exact: true,
    });
  const count = endpoint =>
    record.requests.filter(request => request.path.endsWith(endpoint)).length;
  const visibleText = async key => {
    await page
      .getByText(
        await t(key, {
          username: (state.candidates || candidates)[0].username,
          appName,
        }),
        { exact: true }
      )
      .first()
      .waitFor({ state: 'visible' });
  };
  const click = async key => {
    await (await button(key)).click();
    await settle();
  };
  const input = page.getByRole('textbox', {
    name: locale === 'en' ? 'Instagram username' : 'Usuário do Instagram',
    exact: true,
  });
  async function search(value = '@empresa_sintetica_qa910') {
    await input.fill(value);
    await input.press('Enter');
    await settle();
    await visibleText('RESULTS_TITLE');
  }
  async function select(index = 0, keyboard = false) {
    const candidate = (state.candidates || candidates)[index];
    const target = page.getByRole('button', {
      name: await t('SELECT_PROFILE', candidate),
      exact: true,
    });
    if (keyboard) {
      await target.focus();
      await target.press('Enter');
    } else await target.click();
    await settle();
  }
  async function health({ geometry = true } = {}) {
    await verifyConsumedStyles();
    record.styleSheetsConsumed = await captureUsedStyleSheets(page);
    const data = await page.evaluate(() => {
      const appRoot = document.querySelector('#app');
      const componentSection = appRoot.querySelector('section');
      const heading = appRoot.querySelector('h1, h6');
      return {
        ready: window.instagramQa.ready,
        missing: window.instagramQa.missing,
        vueErrors: window.instagramQa.vueErrors,
        vueWarnings: window.instagramQa.vueWarnings,
        text: appRoot.innerText,
        height: appRoot.getBoundingClientRect().height,
        viewport: { width: window.innerWidth, height: window.innerHeight },
        documentWidth: document.documentElement.scrollWidth,
        color: getComputedStyle(appRoot).color,
        background: getComputedStyle(appRoot.querySelector('main'))
          .backgroundColor,
        headingFont: heading ? getComputedStyle(heading).fontSize : null,
        sectionPadding: componentSection
          ? getComputedStyle(componentSection).paddingInlineStart
          : null,
        stylesheets: [
          ...document.querySelectorAll('link[rel="stylesheet"]'),
        ].map(link => ({
          path: new URL(link.href).pathname,
          loaded: Boolean(link.sheet),
        })),
        controls: [...appRoot.querySelectorAll('button, input, a')]
          .filter(element => element.getBoundingClientRect().height > 0)
          .map(element => {
            const rect = element.getBoundingClientRect();
            return {
              tag: element.tagName,
              width: rect.width,
              height: rect.height,
              scrollWidth: element.scrollWidth,
              clientWidth: element.clientWidth,
              text: element.textContent.trim(),
            };
          }),
        overlay: Boolean(document.querySelector('vite-error-overlay')),
      };
    });
    data.toasts = await page.evaluate(readToastEvidence);
    assertToastEvidence(data.toasts, record.expectedToast, data.viewport);
    record.latestHealth = data;
    assert.ok(
      data.ready && data.height > 0 && data.text.trim().length > 20,
      'Blank/unmounted component'
    );
    assert.equal(data.overlay, false, 'Vite error overlay');
    assert.deepEqual(data.missing, [], 'Missing locale keys');
    assert.deepEqual(data.vueErrors, [], 'Vue runtime errors');
    assert.deepEqual(data.vueWarnings, [], 'Vue runtime warnings');
    assert.deepEqual(record.pageErrors, [], 'Unhandled page errors');
    assert.deepEqual(record.consoleErrors, [], 'Unexpected console errors');
    assert.deepEqual(record.routeErrors, [], 'Internal contract mismatch');
    assert.ok(
      !data.text.includes('QA_UPSTREAM_PRIVATE_MARKER_910'),
      'Raw upstream marker leaked to UI'
    );
    assert.ok(
      !data.text.includes('synthetic-selection-'),
      'Selection token leaked to UI'
    );
    for (const path of [build.css, build.utilities])
      assert.ok(
        data.stylesheets.some(sheet => sheet.path === path && sheet.loaded),
        `Missing real stylesheet ${path}`
      );
    if (geometry) {
      assert.ok(
        data.documentWidth <= data.viewport.width + 1,
        `Horizontal overflow: ${data.documentWidth} > ${data.viewport.width}`
      );
      for (const control of data.controls) {
        assert.ok(
          control.width >= 44 && control.height >= 44,
          `Small interactive target: ${control.tag} ${control.text} ${control.width}x${control.height}`
        );
        if (control.tag !== 'INPUT')
          assert.ok(
            control.scrollWidth <= control.clientWidth + 1,
            `Clipped control label: ${control.text}`
          );
      }
    }
    return data;
  }
  async function guidance(stage = 'guidance') {
    const text = await page.locator('ol').innerText();
    const candidate = (state.candidates || candidates)[0];
    for (const fragment of locale === 'en'
      ? [
          'computer',
          `@${candidate.username}`,
          'Apps and websites',
          'Tester invites',
          appName,
          'Accept',
        ]
      : [
          'computador',
          `@${candidate.username}`,
          'Apps e sites',
          'Convites do testador',
          appName,
          'Aceitar',
        ])
      assert.ok(
        text.includes(fragment),
        `Missing exact acceptance instruction: ${fragment}`
      );
    const link = page.getByRole('link', {
      name: await t('OPEN_APPS'),
      exact: true,
    });
    assert.equal(await link.getAttribute('href'), acceptanceUrl);
    assert.equal(await link.getAttribute('target'), '_blank');
    const rel = (await link.getAttribute('rel')).split(' ');
    assert.ok(
      rel.includes('noopener') && rel.includes('noreferrer'),
      'Unsafe acceptance link'
    );
    assert.equal(
      await (await continueButton()).count(),
      0,
      'OAuth available before acceptance'
    );
    assert.equal(
      await (await button('INVITE')).count(),
      0,
      'Pending profile exposes invite'
    );
    const markers = await page.locator('ol').evaluate(element => ({
      type: getComputedStyle(element).listStyleType,
      items: [...element.children].map(item => ({
        type: getComputedStyle(item).listStyleType,
        display: getComputedStyle(item).display,
        content: getComputedStyle(item, '::marker').content,
        fontSize: getComputedStyle(item, '::marker').fontSize,
      })),
    }));
    record.visualChecks.push({
      stage,
      kind: 'ordered-instructions',
      ...markers,
    });
    assert.equal(
      markers.type,
      'decimal',
      'Acceptance instructions use non-decimal markers'
    );
    assert.equal(markers.items.length, 4);
    for (const item of markers.items) {
      assert.equal(item.type, 'decimal');
      assert.equal(item.display, 'list-item');
      assert.ok(
        !['none', '""'].includes(item.content) &&
          Number.parseFloat(item.fontSize) > 0,
        'Acceptance step marker is hidden'
      );
    }
    const help = page.getByText(
      await t('MISSING_INVITE_HELP', { username: candidate.username, appName }),
      { exact: true }
    );
    const placement = await section
      .locator('button.text-white')
      .last()
      .evaluate(
        (element, paragraph) => ({
          followsInDom:
            element.compareDocumentPosition(paragraph) ===
            Node.DOCUMENT_POSITION_FOLLOWING,
          ctaBottom: element.getBoundingClientRect().bottom,
          helpTop: paragraph.getBoundingClientRect().top,
        }),
        await help.elementHandle()
      );
    record.visualChecks.push({
      stage,
      kind: 'troubleshooting-after-cta',
      ...placement,
    });
    assert.equal(
      placement.followsInDom,
      true,
      'Troubleshooting precedes the CTA in DOM order'
    );
    assert.ok(
      placement.helpTop >= placement.ctaBottom,
      'Troubleshooting appears above/over the CTA'
    );
  }
  async function visualRegression(stage) {
    // Only the assisted flow changed; legacy screenshots remain regression evidence.
    if (!(await section.count())) return;
    const previousFocus = await page.evaluateHandle(
      () => document.activeElement
    );
    async function appearance(target, kind, interaction) {
      await target.evaluate(async element => {
        const animations = element
          .getAnimations()
          .filter(
            animation =>
              animation.effect.getComputedTiming().iterations !== Infinity
          );
        await Promise.all(animations.map(animation => animation.finished));
      });
      const measured = await target.evaluate((element, type) => {
        const text =
          type === 'solid-button'
            ? element.querySelector('span.whitespace-normal') || element
            : element;
        return {
          ...window.instagramQa.appearance(
            text,
            type === 'placeholder' ? '::placeholder' : null
          ),
          focusVisible: element.matches(':focus-visible'),
        };
      }, kind);
      record.visualChecks.push({
        stage,
        kind,
        interaction,
        minimum: MINIMUM_TEXT_CONTRAST,
        ...measured,
      });
      assert.ok(
        measured.contrast >= MINIMUM_TEXT_CONTRAST,
        `${kind} ${interaction} contrast ${measured.contrast.toFixed(3)} < ${MINIMUM_TEXT_CONTRAST}: ${measured.text}`
      );
      if (
        ['solid-button', 'placeholder'].includes(kind) &&
        interaction === 'focus'
      )
        assert.equal(
          measured.focusVisible,
          true,
          'Contrast focus measurement did not activate keyboard focus'
        );
    }
    try {
      if (stage === 'profile') {
        assert.equal(
          await input.count(),
          1,
          'Initial profile placeholder target is missing'
        );
        assert.equal(
          await input.inputValue(),
          '',
          'Placeholder measurement requires an empty input'
        );
        assert.equal(
          await input.evaluate(element =>
            element.matches(':placeholder-shown')
          ),
          true,
          'Initial profile placeholder is not displayed'
        );
        await page.mouse.move(0, 0);
        await input.evaluate(element => element.blur());
        await appearance(input, 'placeholder', 'normal');
        await page.keyboard.press('Tab');
        await input.focus();
        await appearance(input, 'placeholder', 'focus');
      }
      const primaryButtons = await section
        .locator('button.text-white')
        .evaluateAll(elements =>
          elements.map(element => ({
            label: element.textContent.trim(),
            disabled: element.disabled,
          }))
        );
      const primaryCoverage = primaryButtonCoverage(
        primaryButtons,
        options.restricted === true
      );
      record.visualChecks.push({
        stage,
        kind: 'primary-button-contract',
        ...primaryCoverage,
        primaryButtons,
      });
      if (options.restricted)
        assert.equal(
          record.requests.filter(
            request => !request.path.endsWith('/configuration')
          ).length,
          0,
          'Restricted screen sent a non-configuration request'
        );
      const solidButtons = section.locator('button.text-white:enabled');
      for (const index of Array.from(
        { length: await solidButtons.count() },
        (value, position) => position
      )) {
        const target = solidButtons.nth(index);
        await page.mouse.move(0, 0);
        await target.evaluate(element => element.blur());
        await appearance(target, 'solid-button', 'normal');
        await target.hover();
        await appearance(target, 'solid-button', 'hover');
        await page.mouse.move(0, 0);
        await page.keyboard.press('Tab');
        await target.focus();
        await appearance(target, 'solid-button', 'focus');
      }
      const acceptedTitle = page.getByRole('heading', {
        name: await t('CONFIRMED_TITLE'),
        exact: true,
      });
      if (stage === 'accepted')
        assert.equal(
          await acceptedTitle.count(),
          1,
          'Accepted-title contrast target is missing'
        );
      if (await acceptedTitle.count()) {
        await page.mouse.move(0, 0);
        await acceptedTitle.evaluate(element => element.blur());
        await appearance(acceptedTitle, 'accepted-title', 'normal');
        await acceptedTitle.hover();
        await appearance(acceptedTitle, 'accepted-title', 'hover');
        await page.mouse.move(0, 0);
        await page.keyboard.press('Tab');
        await acceptedTitle.focus();
        await appearance(acceptedTitle, 'accepted-title', 'focus');
      }
    } finally {
      await page.mouse.move(0, 0);
      await page.evaluate(element => {
        document.activeElement?.blur();
        if (element?.isConnected) element.focus({ preventScroll: true });
      }, previousFocus);
      await previousFocus.dispose();
    }
    const changeButton = await button('CHANGE_PROFILE');
    if (viewport.width < 640 && (await changeButton.count())) {
      const identity = await changeButton.evaluate(element => {
        const group = element.parentElement;
        const row = group.firstElementChild;
        const text = row.lastElementChild;
        const handle = text.firstElementChild;
        const name = text.lastElementChild;
        const bounds = target => {
          const rect = target.getBoundingClientRect();
          return {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
            bottom: rect.bottom,
          };
        };
        const nameNode = name.firstChild;
        let offset = 0;
        const words = name.textContent
          .trim()
          .split(' ')
          .filter(Boolean)
          .map(word => {
            const start = nameNode.textContent.indexOf(word, offset);
            const range = document.createRange();
            range.setStart(nameNode, start);
            range.setEnd(nameNode, start + word.length);
            offset = start + word.length;
            return {
              word,
              fragments: [...range.getClientRects()].filter(
                rect => rect.width > 0
              ).length,
            };
          });
        return {
          group: bounds(group),
          row: bounds(row),
          text: bounds(text),
          avatar: bounds(row.firstElementChild),
          changeButton: bounds(element),
          handle: bounds(handle),
          gap: Number.parseFloat(getComputedStyle(row).columnGap),
          handleLineHeight: Number.parseFloat(
            getComputedStyle(handle).lineHeight
          ),
          handleText: handle.textContent,
          nameText: name.textContent,
          words,
        };
      });
      record.visualChecks.push({
        stage,
        kind: 'mobile-selected-identity',
        ...identity,
      });
      assert.ok(
        identity.row.width >= identity.group.width - 1,
        'Mobile identity does not use full row width'
      );
      assert.ok(
        identity.text.width >=
          identity.row.width - identity.avatar.width - identity.gap - 1,
        'Change button compresses mobile identity text'
      );
      assert.ok(
        identity.changeButton.y >= identity.row.bottom + 1,
        'Mobile change-profile action is not on a separate line'
      );
      assert.ok(
        Math.abs(identity.changeButton.x - identity.row.x) <= 1,
        'Mobile change-profile action is not aligned to the start'
      );
      assert.ok(
        identity.words.every(word => word.fragments === 1),
        'Mobile profile name wraps inside a word'
      );
      if (viewport.width >= 390 && !options.long)
        assert.ok(
          identity.handle.height <= identity.handleLineHeight + 1,
          '390px profile handle wraps because identity is compressed'
        );
    }
    if (await page.locator('ol').count()) await guidance(stage);
  }
  async function shot(stage) {
    await settle();
    const evidence = await health();
    await visualRegression(stage);
    const prefix =
      stage === 'profile' ? 'placeholder-regression' : 'art-regression';
    const path = resolve(output, `${prefix}-${id}-${stage}.png`);
    const capturedAt = new Date().toISOString();
    await page.screenshot({
      path,
      fullPage: true,
      animations: 'disabled',
      caret: 'hide',
    });
    const toastsAfterCapture = await page.evaluate(readToastEvidence);
    assertToastEvidence(toastsAfterCapture, record.expectedToast, viewport);
    const item = {
      case: id,
      stage,
      file: path.slice(output.length + 1),
      bytes: (await stat(path)).size,
      capturedAt,
      viewport,
      theme,
      zoom: options.zoom || 1,
      capture: 'fullPage at actual viewport width',
      documentWidth: evidence.documentWidth,
      toasts: evidence.toasts,
      toastsAfterCapture,
    };
    assert.ok(item.bytes > 0, 'Empty screenshot');
    record.screenshots.push(item.file);
    results.screenshots.push(item);
  }
  async function close() {
    await context.close();
    for (const key of ['searchGate', 'statusGate', 'inviteGate', 'oauthGate'])
      state[key]?.resolve();
  }
  return {
    page,
    context,
    state,
    record,
    blocked,
    t,
    button,
    continueButton,
    count,
    visibleText,
    input,
    search,
    select,
    click,
    settle,
    health,
    shot,
    guidance,
    close,
  };
}

const views = [
  { label: 'desktop', viewport: { width: 1440, height: 900 } },
  { label: 'mobile', viewport: { width: 390, height: 844 } },
  { label: 'narrow', viewport: { width: 320, height: 568 }, long: true },
  { label: 'tablet', viewport: { width: 1024, height: 768 } },
  {
    label: 'desktop-zoom200',
    viewport: { width: 1440, height: 900 },
    zoom: 2,
    long: true,
  },
];
for (const view of views)
  for (const theme of ['light', 'dark']) {
    define(
      `flow-${view.label}-${theme}`,
      {
        ...view,
        theme,
        state: {
          candidates: view.long ? [longCandidate, candidates[1]] : candidates,
        },
      },
      async q => {
        await q.shot('profile');
        await q.search();
        assert.equal(
          q.count('/status'),
          0,
          'Search implicitly selected a result'
        );
        assert.equal(q.count('/invite'), 0);
        assert.equal(await q.page.locator('ul li').count(), 2);
        assert.equal(
          await q.page.locator('img').count(),
          1,
          'Real photo and fallback avatars expected'
        );
        await q.shot('candidates');
        await q.select();
        await q.visibleText('ABSENT_TITLE');
        assert.equal(q.count('/status'), 1);
        assert.equal(
          q.count('/invite'),
          0,
          'Selection sent invite without explicit click'
        );
        await q.shot('absent');
        await q.click('INVITE');
        await q.visibleText('SENT_TITLE');
        assert.equal(q.count('/invite'), 1);
        await q.guidance();
        await q.shot('pending');
        q.state.status = 'pending';
        await q.click('VERIFY');
        await q.visibleText('STILL_PENDING');
        assert.equal(
          q.count('/invite'),
          1,
          'Verification reinvited pending candidate'
        );
        q.state.status = 'accepted';
        await q.click('VERIFY');
        await q.visibleText('CONFIRMED_TITLE');
        assert.equal(
          q.count('/authorization'),
          0,
          'Acceptance auto-started OAuth'
        );
        assert.ok(await (await q.continueButton()).isEnabled());
        await q.shot('accepted');
        q.state.statusResponse = errorResponse('unknown_status', 502);
        await q.click('CHANGE_PROFILE');
        await q.search();
        await q.select();
        await q.visibleText('STATUS_ERROR');
        assert.equal(await (await q.button('INVITE')).count(), 0);
        assert.equal(await (await q.continueButton()).count(), 0);
        await q.shot('status-error');
        return {
          states: [
            'profile',
            'candidates',
            'absent',
            'pending',
            'still pending',
            'accepted',
            'status error',
          ],
          inviteRequests: q.count('/invite'),
        };
      }
    );
  }
for (const theme of ['light', 'dark'])
  define(
    `legacy-feature-off-${theme}`,
    { theme, feature: 'off', state: { legacy: true, oauthGate: deferred() } },
    async q => {
      assert.equal(q.record.requests.length, 0, 'Feature-off called new API');
      assert.equal(await q.input.count(), 0);
      await q.shot('legacy');
      await (await q.continueButton()).click();
      await until(
        () => q.count('/authorization') === 1,
        'Legacy OAuth request missing'
      );
      assert.equal(q.record.requests.length, 1);
      return { requests: 1, testerRequests: 0 };
    }
  );
define(
  'account-feature-off-legacy',
  {
    state: {
      configuration: json({ ...configuration, enabled: false }),
      legacy: true,
    },
  },
  async q => {
    await (await q.continueButton()).waitFor();
    assert.equal(q.record.requests.length, 1);
    assert.equal(q.count('/configuration'), 1);
    assert.equal(await q.input.count(), 0);
  }
);
define('keyboard-focus-labels', {}, async q => {
  assert.equal(await q.input.getAttribute('id'), 'instagram-tester-username');
  assert.equal(await q.input.getAttribute('autocapitalize'), 'none');
  assert.equal(await q.input.getAttribute('spellcheck'), 'false');
  await q.input.focus();
  await q.page.keyboard.press('Tab');
  assert.equal(
    await q.page.evaluate(() => document.activeElement.textContent.trim()),
    await q.t('SEARCH')
  );
  await q.input.fill('@empresa_sintetica_qa910');
  await q.input.press('Enter');
  await q.settle();
  assert.equal(
    await q.page.evaluate(() => document.activeElement.tagName),
    'H2',
    'Results heading did not receive focus'
  );
  await q.page.keyboard.press('Tab');
  assert.equal(
    await q.page.evaluate(() =>
      document.activeElement.getAttribute('aria-label')
    ),
    await q.t('SELECT_PROFILE', candidates[0])
  );
  assert.equal(
    await q.page.evaluate(() =>
      document.activeElement.matches(':focus-visible')
    ),
    true
  );
  await q.page.keyboard.press('Enter');
  await q.settle();
  assert.equal(q.count('/status'), 1);
  await q.click('CHANGE_PROFILE');
  assert.equal(
    await q.page.evaluate(() => document.activeElement.id),
    'instagram-tester-username',
    'Change profile did not restore input focus'
  );
});
define(
  'single-result-still-explicit',
  { state: { candidates: [candidates[0]] } },
  async q => {
    await q.search();
    assert.equal(q.count('/status'), 0);
    await q.select();
    assert.equal(q.count('/status'), 1);
  }
);
define('choose-second-candidate', {}, async q => {
  await q.search();
  await q.select(1);
  assert.ok(
    (await q.page.locator('#app').innerText()).includes(
      `@${candidates[1].username}`
    )
  );
  assert.equal(q.count('/status'), 1);
});
define('invalid-empty-and-empty-results', {}, async q => {
  for (const value of ['', '@@not_valid', 'invalid username', 'a'.repeat(31)]) {
    await q.input.fill(value);
    await q.input.press('Enter');
    await q.visibleText('INVALID_USERNAME');
    assert.equal(await q.input.getAttribute('aria-invalid'), 'true');
  }
  assert.equal(q.count('/search'), 0);
  q.state.search = json({ results: [] });
  await q.search();
  await q.visibleText('EMPTY');
  assert.equal(q.count('/status'), 0);
  assert.equal(q.count('/invite'), 0);
});
define(
  'malformed-search-result',
  { state: { search: json({ results: [{ username: 'incomplete' }] }) } },
  async q => {
    await q.input.fill('@empresa_sintetica_qa910');
    await q.input.press('Enter');
    await q.settle();
    await q.visibleText('SEARCH_ERROR');
    assert.equal(await q.page.locator('ul li').count(), 0);
    assert.equal(q.count('/status'), 0);
  }
);
define(
  'edit-cancels-stale-search',
  { state: { searchGate: deferred() } },
  async q => {
    await q.input.fill('@empresa_sintetica_qa910');
    await q.input.press('Enter');
    await until(() => q.count('/search') === 1, 'Search did not start');
    await q.input.fill('@outra_empresa_sintetica_qa');
    const oldGate = q.state.searchGate;
    delete q.state.searchGate;
    q.state.candidates = [candidates[1]];
    await q.input.press('Enter');
    await q.settle();
    oldGate.resolve();
    await q.visibleText('RESULTS_TITLE');
    await until(
      () =>
        q.record.requests
          .filter(request => request.path.endsWith('/search'))
          .every(request => request.responseStatus),
      'Stale search fixture did not resolve'
    );
    assert.equal(await q.page.locator('ul li').count(), 1);
    assert.ok(
      (await q.page.locator('ul').innerText()).includes(candidates[1].username)
    );
    assert.equal(q.count('/status'), 0);
  }
);
define(
  'pending-guidance-and-blocked-external-link',
  { state: { status: 'pending' } },
  async q => {
    await q.search();
    await q.select();
    await q.guidance();
    const popupPromise = q.context.waitForEvent('page');
    await q.page
      .getByRole('link', { name: await q.t('OPEN_APPS'), exact: true })
      .click();
    const popup = await popupPromise;
    await until(
      () =>
        q.blocked.some(
          item =>
            item.origin === 'https://www.instagram.com' &&
            item.path === '/accounts/manage_access/'
        ),
      'External acceptance navigation escaped/was not blocked'
    );
    await popup.close();
    assert.equal(q.count('/invite'), 0);
    assert.equal(q.count('/authorization'), 0);
    await q.guidance();
  }
);
define(
  'accepted-oauth-only-after-click',
  { state: { status: 'accepted', oauthGate: deferred() } },
  async q => {
    await q.search();
    await q.select();
    await q.visibleText('CONFIRMED_TITLE');
    assert.equal(q.count('/authorization'), 0);
    await (await q.continueButton()).click();
    await until(
      () => q.count('/authorization') === 1,
      'OAuth click did not send selected token'
    );
    await q.visibleText('AUTHORIZING');
    await q.health();
    q.state.oauthGate.resolve();
    await until(
      () => q.blocked.some(item => item.path === '/qa-synthetic-oauth-910'),
      'External OAuth navigation was not blocked'
    );
    q.record.expectedBlockedOAuthNavigation = true;
    return {
      authorizations: 1,
      externalOAuth: 'blocked before network',
      healthVerifiedBeforeNavigation: true,
    };
  }
);
for (const [id, config] of [
  [
    'unavailable-config',
    json({ ...configuration, available: false, app_name: null }),
  ],
  ['missing-app-name', json({ ...configuration, app_name: '' })],
  ['expired-session-config', errorResponse('meta_session_expired')],
])
  define(id, { state: { configuration: config } }, async q => {
    await q.visibleText('UNAVAILABLE');
    assert.equal(await q.input.count(), 0);
    assert.equal(await (await q.continueButton()).count(), 0);
    assert.equal(q.count('/invite'), 0);
    await q.shot('unavailable');
  });
define(
  'expired-session-status',
  { state: { statusResponse: errorResponse('meta_session_expired') } },
  async q => {
    await q.search();
    await q.select();
    await q.visibleText('UNAVAILABLE');
    assert.equal(await (await q.button('INVITE')).count(), 0);
    assert.equal(await (await q.continueButton()).count(), 0);
  }
);
define(
  'malformed-status-never-absent',
  { state: { statusResponse: json({ status: 'CONFIRMED' }) } },
  async q => {
    await q.search();
    await q.select();
    await q.visibleText('STATUS_ERROR');
    assert.equal(await (await q.button('INVITE')).count(), 0);
    assert.equal(await (await q.continueButton()).count(), 0);
    assert.equal(q.count('/invite'), 0);
  }
);
define(
  'expired-selection',
  { state: { statusResponse: errorResponse('invalid_selection', 422) } },
  async q => {
    await q.search();
    await q.select();
    await q.visibleText('INVALID_SELECTION');
    assert.equal(
      await q.page.evaluate(() => document.activeElement.id),
      'instagram-tester-username'
    );
    assert.equal(q.count('/invite'), 0);
  }
);
define(
  'double-invite-prevented',
  { state: { inviteGate: deferred() } },
  async q => {
    await q.search();
    await q.select();
    const target = await q.button('INVITE');
    await target.evaluate(element => {
      element.click();
      element.click();
    });
    await until(() => q.count('/invite') === 1, 'Invite missing');
    await q.visibleText('INVITING');
    assert.ok(await (await q.button('INVITING')).isDisabled());
    assert.ok(await (await q.button('CHANGE_PROFILE')).isDisabled());
    q.state.inviteGate.resolve();
    await q.settle();
    await q.guidance();
    assert.equal(q.count('/invite'), 1);
  }
);
define(
  'invite-timeout-reconcile-no-loop',
  { state: { invite: errorResponse('invite_unknown') } },
  async q => {
    await q.search();
    await q.select();
    await q.click('INVITE');
    await q.visibleText('INVITE_UNKNOWN');
    assert.equal(q.count('/invite'), 1);
    assert.equal(await (await q.button('INVITE')).count(), 0);
    assert.equal(await (await q.continueButton()).count(), 0);
    await q.shot('indeterminate');
    q.state.status = 'pending';
    await q.click('CHECK_INVITE');
    await q.guidance();
    assert.equal(q.count('/status'), 2);
    assert.equal(q.count('/invite'), 1, 'Timeout blindly retried invite');
  }
);
define(
  'malformed-invite-indeterminate',
  { state: { invite: json({ status: 'accepted', invited: 'true' }) } },
  async q => {
    await q.search();
    await q.select();
    await q.click('INVITE');
    await q.visibleText('INVITE_UNKNOWN');
    assert.equal(await (await q.continueButton()).count(), 0);
    assert.equal(await (await q.button('INVITE')).count(), 0);
  }
);
define(
  'meta-restriction-blocks-tester-network',
  { restricted: true },
  async q => {
    assert.equal(q.count('/configuration'), 1);
    assert.ok(await (await q.button('SEARCH')).isDisabled());
    await q.input.fill('@empresa_sintetica_qa910');
    await q.input.press('Enter');
    await q.settle();
    assert.equal(
      q.count('/search'),
      0,
      'Restricted form sent a forbidden search'
    );
    for (const endpoint of ['/status', '/invite', '/authorization'])
      assert.equal(q.count(endpoint), 0);
    await q.shot('restricted');
  }
);
for (const operation of ['search', 'status'])
  define(
    `proxy-unavailable-${operation}-recovery`,
    {
      state:
        operation === 'search'
          ? { search: errorResponse('proxy_unavailable') }
          : { statusResponse: errorResponse('proxy_unavailable') },
    },
    async q => {
      if (operation === 'search') {
        await q.input.fill('@empresa_sintetica_qa910');
        await q.input.press('Enter');
        await q.settle();
      } else {
        await q.search();
        await q.select();
      }
      await q.visibleText('UNAVAILABLE');
      assert.equal(q.count('/invite'), 0);
      assert.equal(q.count('/authorization'), 0);
      await q.shot(`proxy-${operation}-unavailable`);
      // Operational recovery is injected; this does not repair a real proxy.
      q.state.search = undefined;
      q.state.statusResponse = undefined;
      if (operation === 'search') {
        await q.search();
        await q.select();
        assert.equal(q.count('/search'), 2);
        assert.equal(q.count('/status'), 1);
      } else {
        assert.equal(
          await q.input.count(),
          0,
          'Status failure unexpectedly discarded selected profile'
        );
        await q.page
          .getByText(`@${candidates[0].username}`, { exact: true })
          .waitFor();
        assert.equal(q.count('/search'), 1);
        assert.equal(q.count('/status'), 1);
        assert.ok(
          await (await q.button('CHECK_INVITE')).isEnabled(),
          'Selected profile has no status recovery CTA'
        );
        const retryRequest = q.page.waitForRequest(
          request =>
            new URL(request.url()).pathname ===
              '/api/v1/accounts/910/instagram/testers/status' &&
            request.method() === 'POST'
        );
        await q.click('CHECK_INVITE');
        assert.deepEqual(
          (await retryRequest).postDataJSON(),
          { selection_token: candidates[0].selection_token },
          'Status recovery changed the selected-profile body'
        );
        assert.equal(
          q.count('/search'),
          1,
          'Status retry searched instead of retaining selection'
        );
        assert.equal(q.count('/status'), 2);
      }
      await q.visibleText('ABSENT_TITLE');
      assert.equal(
        await q.page.getByRole('alert').count(),
        0,
        'Successful recovery retained an error'
      );
      assert.ok(await (await q.button('INVITE')).isEnabled());
      assert.equal(q.count('/invite'), 0);
      assert.equal(q.count('/authorization'), 0);
      const failed = q.record.requests.filter(
        item =>
          item.path.endsWith(`/${operation}`) && item.responseStatus === 503
      );
      const recovered = q.record.requests.filter(
        item =>
          item.path.endsWith(`/${operation}`) && item.responseStatus === 200
      );
      assert.equal(failed.length, 1);
      assert.equal(recovered.length, 1);
      assert.ok(
        [...failed, ...recovered].every(item => item.contractValidated)
      );
      return {
        recovery: 'synthetic backend response restored',
        failedContracts: q.record.requests.filter(
          item => item.responseStatus === 503
        ).length,
      };
    }
  );
define(
  'legacy-oauth-failure-clears-loading',
  {
    feature: 'off',
    state: {
      legacy: true,
      authorization: errorResponse('synthetic_authorization_failed', 503),
    },
  },
  async q => {
    const target = await q.continueButton();
    const message = await q.page.evaluate(() =>
      window.instagramQa.t('INBOX_MGMT.ADD.INSTAGRAM.ERROR_AUTH')
    );
    assert.ok(message && message !== 'INBOX_MGMT.ADD.INSTAGRAM.ERROR_AUTH');
    const toast = q.page
      .locator('[data-instagram-qa-toasts]')
      .getByText(message, { exact: true });
    q.record.toastRecovery = [];
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      q.state.oauthGate = deferred();
      q.state.authorizationTimeout = attempt === 1;
      const isAuthorization = request =>
        new URL(request.url()).pathname ===
          '/api/v1/accounts/910/instagram/authorization' &&
        request.method() === 'POST';
      const requested = q.page.waitForRequest(isAuthorization);
      const failed =
        attempt === 1
          ? q.page.waitForEvent('requestfailed', { predicate: isAuthorization })
          : q.page.waitForResponse(
              response =>
                isAuthorization(response.request()) && response.status() === 503
            );
      q.record.expectedToast = message;
      await target.click();
      const request = await requested;
      assert.equal(request.postData(), null, 'Legacy OAuth must send no body');
      assert.equal(
        await target.isDisabled(),
        true,
        'Legacy OAuth loading never started'
      );
      q.state.oauthGate.resolve();
      const failure = await failed;
      if (attempt === 1)
        assert.equal(failure.failure().errorText, 'net::ERR_TIMED_OUT');
      await toast.waitFor({ state: 'visible' });
      await until(
        () => target.isEnabled(),
        'Legacy OAuth loading did not clear'
      );
      assert.equal(q.count('/authorization'), attempt);
      assert.ok(q.record.requests.every(item => item.contractValidated));
      const health = await q.health();
      q.record.toastRecovery.push({
        attempt,
        failure:
          attempt === 1 ? 'synthetic transport timedout' : 'synthetic HTTP 503',
        checkedAt: new Date().toISOString(),
        loadingCleared: true,
        requests: q.count('/authorization'),
        toasts: health.toasts,
      });
      if (attempt === 1) {
        await toast.waitFor({ state: 'hidden' });
        q.record.expectedToast = '';
        await q.health();
      }
    }
    assert.equal(q.count('/configuration'), 0);
    assert.equal(q.count('/authorization'), 2);
    assert.equal(
      q.blocked.length,
      0,
      'Failed legacy OAuth must not navigate externally'
    );
    await q.shot('legacy-recovery');
    return {
      attempts: 2,
      failures: ['synthetic transport timedout', 'synthetic HTTP 503'],
      realToast: true,
    };
  }
);
for (const feature of ['on', 'off'])
  define(
    `oauth-plan-limit-${feature}`,
    {
      feature,
      query: {
        error_type: 'LimitExceeded',
        code: '402',
        error_message: 'QA_UPSTREAM_PRIVATE_MARKER_910',
      },
    },
    async q => {
      const copy = await q.page.evaluate(() =>
        window.instagramQa.t('INBOX_MGMT.ADD.INSTAGRAM.ERROR_INBOX_LIMIT')
      );
      await q.page.getByText(copy, { exact: true }).first().waitFor();
      assert.equal(q.count('/authorization'), 0);
      await q.shot('plan-limit');
    }
  );
define(
  'english-smoke',
  {
    locale: 'en',
    viewport: { width: 390, height: 844 },
    state: { status: 'pending' },
  },
  async q => {
    await q.search();
    await q.select();
    await q.guidance();
    await q.shot('pending-en');
    q.state.status = 'accepted';
    await q.click('VERIFY');
    await q.visibleText('CONFIRMED_TITLE');
    assert.equal(q.count('/authorization'), 0);
  }
);

results.cases = definitions.map(({ id, options }) => ({
  id,
  status: 'BLOCKED',
  reason: 'Not executed',
  viewport: options.viewport || { width: 1440, height: 900 },
  theme: options.theme || 'light',
  locale: options.locale || 'pt_BR',
  zoom: options.zoom || 1,
}));
try {
  await mkdir(output, { recursive: true });
  results.sourceHashes = await fingerprints();
  results.sourceHashesBefore = results.sourceHashes;
  const modulePath = process.env.PLAYWRIGHT_MODULE_PATH;
  if (!modulePath)
    throw new Error(
      'PLAYWRIGHT_MODULE_PATH must point to an already installed Playwright module; no downloads are allowed'
    );
  const entry = extname(modulePath)
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
    name: 'Chromium',
    version: browser.version(),
    isolated: true,
  };
  for (const [index, definition] of definitions.entries()) {
    const result = results.cases[index];
    delete result.reason;
    let q;
    try {
      q = await openScreen(definition.id, definition.options);
      result.evidence = (await definition.action(q)) || {};
      if (!q.record.expectedBlockedOAuthNavigation) await q.health();
      result.status = 'PASS';
      process.stdout.write(`PASS ${definition.id}\n`);
    } catch (error) {
      result.status = 'FAIL';
      result.error = error.message;
      process.stdout.write(`FAIL ${definition.id}: ${error.message}\n`);
    } finally {
      await q?.close();
    }
  }
  results.dependencyMap = await dependencyMap(
    root,
    server,
    results.sourceHashesBefore,
    build.physicalRoots
  );
  results.stylesConsumedHashes = consumedStyleFingerprints(
    results.screens,
    build
  );
  results.styleHashesAfter = await styleFingerprints(root, build);
  assert.deepEqual(
    results.styleHashesAfter,
    results.styleHashesBefore,
    'CSS changed during capture'
  );
  results.sourceHashesAfter = await fingerprints();
  assert.deepEqual(
    results.sourceHashesAfter,
    results.sourceHashesBefore,
    'Source changed during browser QA; rerun against stable component code'
  );
} catch (error) {
  results.fatal = error.message;
  process.stderr.write(`BLOCKED ${error.message}\n`);
} finally {
  await browser?.close();
  await server?.close();
  results.finishedAt = new Date().toISOString();
  results.counts = Object.fromEntries(
    ['PASS', 'FAIL', 'BLOCKED'].map(status => [
      status.toLowerCase(),
      results.cases.filter(item => item.status === status).length,
    ])
  );
  results.status = 'PASS';
  if (results.counts.fail) results.status = 'FAIL';
  if (results.fatal || results.counts.blocked) results.status = 'BLOCKED';
  await mkdir(output, { recursive: true });
  await writeFile(
    resolve(output, 'results.json'),
    JSON.stringify(results, null, 2)
  );
  process.stdout.write(
    JSON.stringify({
      status: results.status,
      ...results.counts,
      screenshots: results.screenshots.length,
    }) + '\n'
  );
  if (results.status !== 'PASS') process.exitCode = 1;
}
