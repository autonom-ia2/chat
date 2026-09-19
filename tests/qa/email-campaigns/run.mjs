import { writeFile, readFile, stat } from 'node:fs/promises';
import { installDomHelpers } from './browser-helpers.mjs';
import { resolve } from 'node:path';
import { startServer, output } from './server.mjs';
import { responseFor, current, recipients } from './fixtures.mjs';
import { chromium } from '../../playwright/node_modules/playwright/index.mjs';

const results = {
  startedAt: new Date().toISOString(),
  scope:
    'Real CrmCampaignManagementPage and children + dashboard CSS/current production Tailwind utilities; isolated page, no navigation/sidebar shell; synthetic HTTP fixtures, not backend E2E',
  checks: [],
  screens: [],
  screenshots: [],
  requests: [],
  blockedExternal: [],
};
let browser;
let server;
const check = async (name, action) => {
  try {
    const evidence = await action();
    results.checks.push({ name, status: 'PASS', evidence });
    console.log(`PASS ${name}`);
  } catch (error) {
    results.checks.push({ name, status: 'FAIL', error: error.message });
    console.log(`FAIL ${name}: ${error.message}`);
  }
};
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const save = async () => {
  results.finishedAt = new Date().toISOString();
  results.status = results.fatal
    ? 'BLOCKED'
    : results.checks.some(c => c.status === 'FAIL')
      ? 'NEEDS_FIXES'
      : 'PASS';
  results.counts = {
    screenshots: results.screenshots.length,
    passed: results.checks.filter(c => c.status === 'PASS').length,
    failed: results.checks.filter(c => c.status === 'FAIL').length,
  };
  await writeFile(
    resolve(output, 'results.json'),
    JSON.stringify(results, null, 2)
  );
};
async function openScreen(name, options = {}) {
  const locale = options.locale || 'pt_BR';
  const context = await browser.newContext({
    viewport: options.viewport || { width: 1280, height: 900 },
    locale: locale.replace('_', '-'),
    timezoneId: 'America/Sao_Paulo',
    colorScheme: options.theme || 'light',
    serviceWorkers: 'block',
    permissions: ['clipboard-read', 'clipboard-write'],
  });
  const page = await context.newPage();
  await page.addInitScript(installDomHelpers);
  const pending = new Set();
  page.on('request', request => {
    if (['fetch', 'xhr'].includes(request.resourceType())) pending.add(request);
  });
  page.on('requestfinished', request => pending.delete(request));
  page.on('requestfailed', request => pending.delete(request));
  page.setDefaultTimeout(10000);
  const record = {
    name,
    locale,
    console: [],
    pageErrors: [],
    requestFailures: [],
    screenshots: [],
  };
  results.screens.push(record);
  const state = {
    scenario: options.scenario,
    reportError: false,
    recipientError: false,
  };
  page.on('console', msg =>
    record.console.push({ type: msg.type(), text: msg.text() })
  );
  page.on('pageerror', error => record.pageErrors.push(error.message));
  page.on('requestfailed', request =>
    record.requestFailures.push({
      url: request.url(),
      failure: request.failure(),
    })
  );
  await context.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.hostname !== '127.0.0.1' || url.port !== '3437') {
      results.blockedExternal.push({ screen: name, url: url.href });
      return route.abort('blockedbyclient');
    }
    if (!url.pathname.startsWith('/api/')) return route.continue();
    const response = responseFor(url, request.method(), state);
    results.requests.push({
      screen: name,
      method: request.method(),
      path: url.pathname,
      query: Object.fromEntries(url.searchParams),
      response,
    });
    await route.fulfill(response);
  });
  await page.goto(
    `http://127.0.0.1:3437/app/accounts/436/crm/campaign-management?locale=${locale}&theme=${options.theme || 'light'}&role=${options.role || 'admin'}${options.campaign === false ? '' : `&campaign=${options.campaign || 4361}`}`
  );
  await page.waitForFunction(() => window.__qa?.ready === true, null, {
    timeout: 60000,
  });
  const scroller = page.locator('#app > .overflow-y-auto');
  await scroller.waitFor();
  if (options.contentWidth) {
    await scroller.evaluate((element, width) => {
      element.style.width = `${width}px`;
      element.style.maxWidth = `${width}px`;
      element.style.marginInlineStart = 'auto';
    }, options.contentWidth);
  }
  await page.evaluate(() => document.fonts.ready);
  async function settle() {
    const deadline = Date.now() + 10000;
    let previous;
    let stable = 0;
    while (Date.now() < deadline) {
      const geometry = await page.evaluate(() => {
        const root = document.querySelector('#app > .overflow-y-auto');
        return JSON.stringify([
          root.scrollHeight,
          root.clientHeight,
          root.innerText,
          ...[...root.querySelectorAll('section, table')].map(element => {
            const rect = element.getBoundingClientRect();
            return [rect.width, rect.height];
          }),
        ]);
      });
      stable = pending.size === 0 && geometry === previous ? stable + 1 : 0;
      if (stable >= 3) return;
      previous = geometry;
      await page.waitForTimeout(100);
    }
    throw new Error(
      `Page did not settle: ${pending.size} active fetch/XHR requests`
    );
  }
  await settle();
  const t = (key, values) =>
    page.evaluate(
      ([message, params]) => window.__qa.t(message, params),
      [key, values]
    );
  const ns = (key, values) => t(`EMAIL_CAMPAIGN_PROTECTION.${key}`, values);
  const section = page.locator('section').filter({
    has: page.getByRole('heading', {
      name: await t('CAMPAIGN_MANAGEMENT.RECIPIENTS.TITLE'),
      exact: true,
    }),
  });
  const campaignFilterGroup = page.getByRole('group', {
    name: await t('CAMPAIGN_MANAGEMENT.FILTER.LABEL'),
    exact: true,
  });
  const recipientFilterGroup = section.getByRole('group', {
    name: await t('CAMPAIGN_MANAGEMENT.TABLE.STATUS'),
    exact: true,
  });

  async function dropdownItems(group) {
    const trigger = group.getByRole('button').first();
    await trigger.click();
    const floating = page.locator('[data-dropdown-menu]:visible').last();
    if (await floating.count()) {
      return { trigger, items: floating.locator('li.n-dropdown-item > *') };
    }
    return {
      trigger,
      items: group.locator('li.n-dropdown-item > *:visible'),
    };
  }

  async function chooseDropdown(group, index) {
    const { items } = await dropdownItems(group);
    assert((await items.count()) > index, `Missing dropdown option ${index}`);
    await items.nth(index).click();
    await settle();
  }

  async function countDropdownOptions(group) {
    const { trigger, items } = await dropdownItems(group);
    const count = await items.count();
    await trigger.click();
    await settle();
    return count;
  }

  const recipientStatusIndex = {
    '': 0,
    pending: 1,
    delivered: 2,
    attention: 3,
    unsubscribed: 4,
  };
  const problemStatusIndex = {
    attention: 0,
    temporary_bounced: 1,
    hard_bounced: 2,
    complained: 3,
    preflight_invalid: 4,
    preflight_review: 5,
  };

  const selectCampaign = value =>
    chooseDropdown(campaignFilterGroup, value ? Number(value) - 4360 : 0);
  const campaignOptionCount = () => countDropdownOptions(campaignFilterGroup);
  const campaignSelectionLabel = () =>
    campaignFilterGroup.getByRole('button').first().innerText();
  const selectRecipientStatus = value =>
    chooseDropdown(recipientFilterGroup, recipientStatusIndex[value]);
  const recipientOptionCount = () => countDropdownOptions(recipientFilterGroup);
  const recipientSelectionLabel = () =>
    recipientFilterGroup.getByRole('button').first().innerText();
  async function selectProblemStatus(value) {
    const problemGroup = section.getByRole('group', {
      name: await ns('STATUS.attention'),
      exact: true,
    });
    await chooseDropdown(problemGroup, problemStatusIndex[value]);
  }
  async function shot(suffix, target, { sequence = true } = {}) {
    await settle();
    const range = await scroller.evaluate(
      (root, target) => {
        const rootRect = root.getBoundingClientRect();
        const rect = target?.getBoundingClientRect();
        return {
          top: rect ? rect.top - rootRect.top + root.scrollTop : 0,
          height: rect ? rect.height : root.scrollHeight,
          viewport: root.clientHeight,
          max: root.scrollHeight - root.clientHeight,
          current: root.scrollTop,
        };
      },
      target ? await target.elementHandle() : null
    );
    assert(
      range.height > 0 && range.viewport > 0,
      `Zero-height capture target: ${suffix}`
    );
    const positions = [];
    if (!sequence) positions.push(range.current);
    else {
      const step = Math.max(1, range.viewport - 64);
      for (let offset = 0; ; offset += step) {
        const y = Math.max(0, Math.min(range.top + offset, range.max));
        if (positions.at(-1) === y) break;
        positions.push(y);
        if (y + range.viewport >= range.top + range.height - 1) break;
      }
    }
    for (const [index, y] of positions.entries()) {
      await scroller.evaluate(
        (root, y) => root.scrollTo({ top: y, behavior: 'instant' }),
        y
      );
      await settle();
      const coordinates = await page.evaluate(() => {
        const root = document.querySelector('#app > .overflow-y-auto');
        const tables = [...root.querySelectorAll('table')].map(table => ({
          x: table.parentElement.scrollLeft,
          width: table.parentElement.clientWidth,
          scrollWidth: table.parentElement.scrollWidth,
        }));
        const focus = document.activeElement;
        return {
          scrollTop: root.scrollTop,
          clientHeight: root.clientHeight,
          scrollHeight: root.scrollHeight,
          viewport: { width: innerWidth, height: innerHeight },
          tables,
          focus: {
            tag: focus?.tagName,
            text: focus?.textContent?.trim().slice(0, 100),
            focusVisible: focus?.matches(':focus-visible'),
          },
        };
      });
      let clip;
      if (target) {
        const bounds = await target.boundingBox();
        const container = await scroller.boundingBox();
        assert(
          bounds && bounds.height > 0 && container,
          `Detached/empty target: ${suffix}`
        );
        const x = Math.max(0, bounds.x, container.x);
        const top = Math.max(0, bounds.y, container.y);
        const right = Math.min(
          coordinates.viewport.width,
          bounds.x + bounds.width,
          container.x + container.width
        );
        const bottom = Math.min(
          coordinates.viewport.height,
          bounds.y + bounds.height,
          container.y + container.height
        );
        clip = { x, y: top, width: right - x, height: bottom - top };
        assert(
          clip.width > 0 && clip.height > 0,
          `Target outside actual scroll viewport: ${suffix}`
        );
      }
      const tableX = Math.round(coordinates.tables.at(-1)?.x || 0);
      const path = resolve(
        output,
        `${name}-${suffix}-${String(index + 1).padStart(2, '0')}-y${Math.round(coordinates.scrollTop)}-x${tableX}.png`
      );
      assert(pending.size === 0, 'Active fetch immediately before screenshot');
      await page.screenshot({
        path,
        fullPage: false,
        ...(clip ? { clip } : {}),
        animations: 'disabled',
        caret: 'hide',
      });
      const bytes = (await stat(path)).size;
      results.screenshots.push(path);
      record.screenshots.push({
        path,
        bytes,
        clip,
        ...coordinates,
        activeRequests: pending.size,
      });
      assert(
        bytes > 0 && pending.size === 0,
        `Capture was not stable: ${path}`
      );
    }
  }
  const latest = suffix =>
    results.requests
      .filter(r => r.screen === name && r.path.endsWith(suffix))
      .at(-1);
  async function requestAfter(suffix, action) {
    const waiter = page.waitForResponse(r =>
      new URL(r.url()).pathname.endsWith(suffix)
    );
    await action();
    await waiter;
    await settle();
    return latest(suffix);
  }
  async function inspect() {
    await settle();
    record.runtime = await page.evaluate(() => ({
      missing: [...new Set(window.__qa.missing.map(x => x.key))],
      vueErrors: window.__qa.vueErrors,
      vueWarnings: window.__qa.vueWarnings,
      text: document.body.innerText,
    }));
    record.layout = await page.evaluate(() => {
      const rect = e => {
        const r = e.getBoundingClientRect();
        const c = getComputedStyle(e);
        return {
          text: (e.innerText || e.getAttribute('aria-label') || '').slice(
            0,
            140
          ),
          x: r.x,
          y: r.y,
          width: r.width,
          height: r.height,
          clientWidth: e.clientWidth,
          scrollWidth: e.scrollWidth,
          direction: c.direction,
          unicodeBidi: c.unicodeBidi,
          minWidth: c.minWidth,
          color: c.color,
          background: c.backgroundColor,
          fontSize: c.fontSize,
          padding: c.padding,
          overflowX: c.overflowX,
        };
      };
      return {
        viewport: innerWidth,
        viewportHeight: innerHeight,
        pageContainer: {
          ...rect(document.querySelector('#app > .overflow-y-auto')),
          overflowY: getComputedStyle(
            document.querySelector('#app > .overflow-y-auto')
          ).overflowY,
        },
        stylesheets: [...document.styleSheets].map(sheet => sheet.href),
        documentWidth: document.documentElement.scrollWidth,
        bodyWidth: document.body.scrollWidth,
        dark: document.documentElement.classList.contains('dark'),
        direction: document.documentElement.dir,
        badges: [...document.querySelectorAll('[data-email-status-badge]')]
          .filter(window.__qaDom.isExposed)
          .map(rect),
        buttons: [...document.querySelectorAll('button')]
          .filter(window.__qaDom.isExposed)
          .map(rect),
        icons: [
          ...document.querySelectorAll(
            'button span[class*="i-lucide"], span[aria-hidden="true"][class*="i-lucide"]'
          ),
        ]
          .filter(window.__qaDom.isExposed)
          .map(rect),
        tables: [...document.querySelectorAll('table')]
          .filter(window.__qaDom.isExposed)
          .map(rect),
        controls: [...document.querySelectorAll('input, select')].map(rect),
        emailFields: [...document.querySelectorAll('td > bdi')].map(rect),
        recipientRows: [...document.querySelectorAll('tr')]
          .filter(row => row.querySelector('td > bdi'))
          .map(rect),
        panels: [...document.querySelectorAll('section')].map(rect),
      };
    });
    await writeFile(resolve(output, `${name}-dom.txt`), record.runtime.text);
    await writeFile(
      resolve(output, `${name}-aria.yml`),
      await page.locator('body').ariaSnapshot()
    );
  }
  return {
    context,
    page,
    record,
    state,
    t,
    ns,
    section,
    campaignFilterGroup,
    recipientFilterGroup,
    dropdownItems,
    selectCampaign,
    campaignOptionCount,
    campaignSelectionLabel,
    selectRecipientStatus,
    recipientOptionCount,
    recipientSelectionLabel,
    selectProblemStatus,
    shot,
    latest,
    requestAfter,
    inspect,
    settle,
    scroller,
  };
}
async function smoke(screen) {
  const { page, record, inspect, shot } = screen;
  await inspect();
  record.initialLayout = record.layout;
  if (screen.state.scenario === 'import-populations') {
    await check(
      `${record.name}: original import and unsent analysis remain separate`,
      async () => {
        const number = value =>
          new Intl.NumberFormat(screen.record.locale.replace('_', '-')).format(
            value
          );
        const original = screen.page
          .getByRole('heading', {
            name: await screen.ns('IMPORT_ORIGINAL'),
            exact: true,
          })
          .locator('..');
        assert(
          (await original.innerText()).includes(
            await screen.ns('IMPORT_SUMMARY', {
              total: number(3),
              imported: number(1),
              duplicates: number(1),
              invalid: number(1),
              suppressed: number(0),
            })
          ),
          'Original import result hidden or changed'
        );
        const hygiene = screen.page
          .getByRole('heading', {
            name: await screen.ns('HYGIENE'),
            exact: true,
          })
          .locator('..');
        assert(
          JSON.stringify(await hygiene.locator('dd').allTextContents()) ===
            JSON.stringify([number(1), number(1)]),
          'Hygiene must show only supplied counts'
        );
        assert(
          !(await hygiene.innerText()).includes(
            await screen.ns('STATUS.duplicate')
          ),
          'Missing duplicate count invented'
        );
        const panel = screen.page.locator('section[aria-live]').first();
        assert(
          (await panel.innerText()).includes(await screen.ns('REASON.review')),
          'Hygiene pause review explanation missing'
        );
        assert(
          (await panel.innerText()).includes(await screen.ns('RECHECK')),
          'Recheck explanation missing'
        );
      }
    );
    await screen.shot('import-populations');
  }
  if (screen.state.scenario === 'mixed-denominator') {
    await check(
      `${record.name}: mixed send reputation denominator uses the verified sending cohort`,
      async () => {
        const cards = screen.page.locator('section.grid > div');
        assert(
          (await cards.nth(0).innerText()).includes('4'),
          'Mixed total lost'
        );
        const sentLabel = await screen.t('CAMPAIGN_MANAGEMENT.KPIS.SENT');
        const permanentLabel = (await screen.ns('STATUS.permanent'))
          .split('—')
          .at(-1)
          .trim();
        const permanent = cards.filter({ hasText: permanentLabel });
        const complaint = cards.filter({
          hasText: await screen.ns('STATUS.complained'),
        });
        assert(
          (await permanent.first().innerText()).includes('100%') &&
            (await permanent.first().innerText()).includes(`${sentLabel}: 1`),
          'Reputation denominator missing from permanent failure rate'
        );
        assert(
          (await complaint.first().innerText()).includes(`${sentLabel}: 1`),
          'Reputation denominator missing from complaint rate'
        );
        assert(
          !/\b(?:SES|Amazon|AWS)\b/i.test(
            await screen.page.locator('body').innerText()
          ),
          'Provider implementation name leaked to customer UI'
        );
      }
    );
    await shot('mixed-denominator');
    await screen.requestAfter('/reports', () => screen.selectCampaign('4361'));
    await inspect();
  }

  await shot('whole');
  await check(`${record.name}: no unhandled runtime errors`, () =>
    assert(
      !record.pageErrors.length && !record.runtime.vueErrors.length,
      JSON.stringify({
        pageErrors: record.pageErrors,
        vueErrors: record.runtime.vueErrors,
      })
    )
  );
  await check(`${record.name}: full locale dictionary without fallback`, () =>
    assert(!record.runtime.missing.length, record.runtime.missing.join(', '))
  );
  await check(`${record.name}: document fits viewport`, () =>
    assert(
      record.layout.documentWidth <= record.layout.viewport + 1,
      `${record.layout.documentWidth}px document > ${record.layout.viewport}px viewport`
    )
  );
  await check(
    `${record.name}: real dashboard styles and bounded internal page scroller`,
    () => {
      assert(
        record.layout.stylesheets.some(href =>
          href?.includes('/vite-test/assets/dashboard-')
        ) &&
          record.layout.stylesheets.some(href =>
            href?.endsWith('/current-utilities.css')
          ),
        'Actual dashboard/current utility stylesheets missing'
      );
      assert(
        record.layout.pageContainer.overflowY === 'auto' &&
          record.layout.pageContainer.height > 0 &&
          record.layout.pageContainer.height <=
            record.layout.viewportHeight + 1,
        'Page capture must use the real bounded scroll container'
      );
      return {
        scope: results.scope,
        pageContainer: record.layout.pageContainer,
        stylesheets: record.layout.stylesheets,
      };
    }
  );
  await check(`${record.name}: real styled badges and finite tables`, () => {
    assert(record.layout.badges.length > 2, 'Badges missing');
    assert(
      record.layout.badges.every(
        b =>
          b.height > 0 &&
          parseFloat(b.padding) > 0 &&
          b.fontSize !== '16px' &&
          b.background !== 'rgba(0, 0, 0, 0)'
      ),
      'Badge styles missing'
    );
    assert(
      record.layout.tables.length > 0 &&
        record.layout.tables.every(
          t => Number.isFinite(t.width) && t.width > 0 && t.height > 0
        ),
      'Table geometry invalid'
    );
    return record.layout.badges.slice(0, 2);
  });
  await check(`${record.name}: buttons and icons have nonzero dimensions`, () =>
    assert(
      record.layout.buttons.every(b => b.width > 0 && b.height > 0) &&
        record.layout.icons.length > 0 &&
        record.layout.icons.every(i => i.width > 0 && i.height > 0),
      'Zero-size button or icon'
    )
  );
  await check(
    `${record.name}: no raw provider diagnostics or technical statuses`,
    () =>
      assert(
        !/SYNTHETIC_PRIVATE_MARKER|hard_bounced|preflight_invalid|temporary_bounced|reputation_guardrail/.test(
          record.runtime.text
        ),
        'Raw machine status/diagnostic visible'
      )
  );
  await check(`${record.name}: labels on inputs and buttons`, async () => {
    const missing = await page.evaluate(() =>
      [...document.querySelectorAll('input,select,button')]
        .filter(e => !e.disabled && window.__qaDom.isExposed(e))
        .filter(
          e =>
            !(
              e.getAttribute('aria-label') ||
              e.getAttribute('aria-labelledby') ||
              e.labels?.length ||
              (e.tagName === 'BUTTON' && e.textContent.trim())
            )
        )
        .map(e => e.outerHTML)
    );
    assert(!missing.length, missing.join('\n'));
  });
  await check(
    `${record.name}: native control text not vertically clipped`,
    async () => {
      const clipped = await page.evaluate(() =>
        [...document.querySelectorAll('button,select')]
          .filter(window.__qaDom.isExposed)
          .filter(e => {
            const c = getComputedStyle(e);
            return (
              e.getBoundingClientRect().height <
              parseFloat(c.lineHeight) +
                parseFloat(c.paddingTop) +
                parseFloat(c.paddingBottom) -
                1
            );
          })
          .map(e => e.textContent.trim())
      );
      assert(!clipped.length, clipped.join(', '));
    }
  );
}
async function keyboardCoverage(screen) {
  const { page, section, shot, ns } = screen;
  const expected = await page.evaluate(() => {
    const buttons = [
      ...document.querySelectorAll('button:not(:disabled)'),
    ].filter(window.__qaDom.isExposed);
    const summaries = [...document.querySelectorAll('summary')].filter(
      window.__qaDom.isExposed
    );
    return [...buttons, ...summaries].map((element, index) => {
      element.dataset.qaKeyboard = String(index);
      return {
        id: String(index),
        tag: element.tagName,
        tabIndex: element.tabIndex,
        label: element.textContent.trim(),
      };
    });
  });
  assert(expected.length > 0, 'No exposed keyboard controls');
  assert(
    expected.every(control => control.tabIndex >= 0),
    `Exposed action removed from Tab order: ${JSON.stringify(expected.filter(control => control.tabIndex < 0))}`
  );
  const seen = new Set();
  await page.evaluate(() => {
    document.body.tabIndex = -1;
    document.body.focus();
    document.body.removeAttribute('tabindex');
  });
  for (
    let i = 0;
    i < expected.length * 12 && seen.size < expected.length;
    i++
  ) {
    await page.keyboard.press('Tab');
    const active = await page.evaluate(() => ({
      id: document.activeElement?.dataset.qaKeyboard,
      tag: document.activeElement?.tagName,
    }));
    if (active.id !== undefined && !seen.has(active.id)) {
      seen.add(active.id);
      if (seen.size === 1 || active.tag === 'SUMMARY')
        await shot(`focus-${active.tag.toLowerCase()}-${active.id}`, null, {
          sequence: false,
        });
    }
  }
  const buttons = expected.filter(control => control.tag === 'BUTTON');
  assert(
    expected.every(control => seen.has(control.id)),
    `Reached ${buttons.filter(control => seen.has(control.id)).length}/${buttons.length} exposed enabled buttons; missing ${JSON.stringify(expected.filter(control => !seen.has(control.id)))}`
  );
  const detailsCount = await section.locator('details:visible').count();
  assert(detailsCount > 0, 'Recipient details missing');
  const detailsEvidence = [];
  for (let index = 0; index < detailsCount; index++) {
    const details = section.locator('details').nth(index);
    const summary = details.locator('summary');
    // Traverse from the current focus with real Tab; never programmatically focus
    // a summary or copy button, which would hide a broken keyboard order.
    let reached = false;
    for (let step = 0; step < expected.length * 12; step++) {
      await page.keyboard.press('Tab');
      if (
        await summary.evaluate(element => document.activeElement === element)
      ) {
        reached = true;
        break;
      }
    }
    assert(reached, `Summary ${index + 1} is unreachable`);
    assert(
      !(await details.evaluate(element => element.open)),
      'Details unexpectedly open before keyboard test'
    );
    await page.keyboard.press('Enter');
    assert(
      await details.evaluate(element => element.open),
      `Summary ${index + 1} did not open via Enter`
    );
    const copy = details.getByRole('button', {
      name: await ns('COPY'),
      exact: true,
    });
    assert(
      await copy.evaluate(
        element => window.__qaDom.isExposed(element) && element.tabIndex >= 0
      ),
      `Copy ${index + 1} is exposed but not focusable`
    );
    await page.keyboard.press('Tab');
    assert(
      await copy.evaluate(element => document.activeElement === element),
      `Copy ${index + 1} not next in Tab order`
    );
    const email = await details.locator('bdi[dir="ltr"]').innerText();
    assert(
      (await details.innerText()).includes(recipients[index].name.trim()),
      `Full recipient name ${index + 1} missing in opened details`
    );
    await page.keyboard.press('Enter');
    await page.waitForFunction(
      email => navigator.clipboard.readText().then(text => text === email),
      email
    );
    assert(
      (await details
        .getByRole('button', { name: await ns('COPIED'), exact: true })
        .count()) === 1,
      'Localized copy confirmation missing'
    );
    await shot(`focus-copy-detail-${index + 1}`, null, { sequence: false });
    detailsEvidence.push({
      index: index + 1,
      email,
      copied: await page.evaluate(() => navigator.clipboard.readText()),
    });
    await page.keyboard.press('Shift+Tab');
    assert(
      await summary.evaluate(element => document.activeElement === element),
      'Cannot return to summary'
    );
    await page.keyboard.press('Enter');
    assert(
      !(await details.evaluate(element => element.open)),
      'Details did not close via Enter'
    );
  }
  return {
    reachedButtons: buttons.filter(control => seen.has(control.id)).length,
    expectedButtons: buttons.length,
    reachedSummaries: expected.filter(
      control => control.tag === 'SUMMARY' && seen.has(control.id)
    ).length,
    totalButtonsIncludingOpenedDetails: buttons.length + detailsEvidence.length,
    openedAndCopiedDetails: detailsEvidence,
  };
}
async function rtlEmails(screen) {
  const { page, section, shot } = screen;
  const collect = locator =>
    locator.evaluateAll(elements =>
      elements.map(element => ({
        tag: element.tagName,
        dir: element.dir,
        direction: getComputedStyle(element).direction,
        unicodeBidi: getComputedStyle(element).unicodeBidi,
        exposed: window.__qaDom.isExposed(element),
        text: element.textContent,
      }))
    );
  const table = section.locator('table:visible').first();
  const rows = table.locator('tbody tr');
  const fields = await collect(table.locator('td > bdi'));
  assert(
    fields.length === (await rows.count()) && fields.length > 0,
    'Missing table email isolation fields'
  );
  const detailsFields = [];
  for (let index = 0; index < fields.length; index++) {
    const details = rows.nth(index).locator('details');
    await details.locator('summary').click();
    const field = await collect(details.locator('bdi'));
    assert(
      field.length === 1 && field[0].exposed,
      `Detail email ${index + 1} missing/hidden`
    );
    assert(
      field[0].text === fields[index].text,
      'Detail address differs from table'
    );
    detailsFields.push(...field);
    if (index === 0) await shot('rtl-open-email', details);
    await details.locator('summary').click();
  }
  assert(
    [...fields, ...detailsFields].every(
      field =>
        field.exposed &&
        field.tag === 'BDI' &&
        field.dir === 'ltr' &&
        field.direction === 'ltr' &&
        field.unicodeBidi === 'isolate'
    ),
    'Email itself is not explicitly LTR and bidi-isolated'
  );
  const localizedDirections = await table
    .locator('tbody tr td:nth-child(3), summary')
    .evaluateAll(elements =>
      elements.map(element => ({
        text: element.textContent,
        direction: getComputedStyle(element).direction,
      }))
    );
  assert(
    localizedDirections.every(
      element =>
        element.direction === 'rtl' && /[\u0600-\u06ff]/.test(element.text)
    ),
    'Localized status/details must remain Arabic RTL'
  );
  return {
    fields,
    detailsFields,
    localizedDirections,
    documentDirection: await page.locator('html').getAttribute('dir'),
  };
}
async function mobileTable(screen) {
  const { section, page, shot } = screen;
  const list = section.locator('[data-recipient-mobile-list]');
  const cards = list.locator('[data-recipient-card]');
  const desktopTable = section.locator('table');

  const geometry = await list.evaluate(element => ({
    width: element.getBoundingClientRect().width,
    scrollWidth: element.scrollWidth,
    overflowX: getComputedStyle(element).overflowX,
    cards: [...element.querySelectorAll('[data-recipient-card]')].map(card => ({
      width: card.getBoundingClientRect().width,
      height: card.getBoundingClientRect().height,
    })),
  }));

  assert(
    geometry.cards.length > 0 &&
      geometry.cards.every(
        card => card.width >= 300 && card.width <= 390 && card.height <= 260
      ),
    `Unreadable mobile recipient cards: ${JSON.stringify(geometry)}`
  );
  assert(
    geometry.scrollWidth <= geometry.width + 1,
    'Mobile recipient cards must not require horizontal scrolling'
  );
  assert(
    (await desktopTable.evaluate(
      element => getComputedStyle(element.parentElement).display
    )) === 'none',
    'Desktop recipient table is still visible on mobile'
  );

  await shot('recipient-cards', section);
  assert(
    page.viewportSize().width === 390 && page.viewportSize().height === 844,
    'Physical mobile viewport changed'
  );

  const details = cards.first().locator('details');
  await details.locator('summary').click();
  assert(
    (await details.innerText()).includes(recipients[0].name.trim()),
    'Full long name inaccessible in mobile details'
  );
  assert(
    (await details.locator('bdi').innerText()) === recipients[0].email,
    'Full long email inaccessible in mobile details'
  );
  await shot('recipient-card-full-identity', details);
  await details.locator('summary').click();

  const documentWidth = await page.evaluate(
    () => document.documentElement.scrollWidth
  );
  assert(documentWidth <= 391, `Mobile document overflowed: ${documentWidth}`);
  return geometry;
}

try {
  ({
    server,
    css: results.css,
    utilities: results.utilities,
  } = await startServer());
  browser = await chromium.launch({
    headless: true,
    executablePath: chromium.executablePath(),
  });
  results.browserVersion = browser.version();
  const desktop = await openScreen('pt-desktop');
  await smoke(desktop);
  const {
    page,
    ns,
    t,
    section,
    campaignFilterGroup,
    recipientFilterGroup,
    dropdownItems,
    selectCampaign,
    campaignOptionCount,
    campaignSelectionLabel,
    selectRecipientStatus,
    recipientOptionCount,
    recipientSelectionLabel,
    selectProblemStatus,
    shot,
    requestAfter,
    latest,
    state,
    settle,
  } = desktop;
  await shot('protection', page.locator('section[aria-live]').first());
  await shot('recipients-before', section);
  await check(
    'PT: customer surface uses Chatwoot controls and hides infrastructure jargon',
    async () => {
      const panelText = await page
        .locator('section[aria-live]')
        .first()
        .innerText();
      const bodyText = await page.locator('body').innerText();
      assert(
        (await page.locator('select').count()) === 0,
        'Native select rendered'
      );
      assert(
        !/\b(?:SES|Amazon|AWS)\b/i.test(bodyText),
        'Infrastructure name leaked'
      );
      assert(
        !panelText.includes('—'),
        'Primary protection panel shows placeholder dash'
      );
      assert(
        !bodyText.includes(await ns('ANALYSIS_ONLY')),
        'Customer surface exposes contradictory analysis-only copy'
      );
    }
  );
  await check(
    'PT: search and primary status filter align cleanly',
    async () => {
      const search = section.getByRole('textbox', {
        name: await ns('SEARCH'),
        exact: true,
      });
      const statusButton = section
        .getByRole('group', {
          name: await t('CAMPAIGN_MANAGEMENT.TABLE.STATUS'),
          exact: true,
        })
        .getByRole('button')
        .first();
      const [searchBox, statusBox] = await Promise.all([
        search.boundingBox(),
        statusButton.boundingBox(),
      ]);
      assert(searchBox && statusBox, 'Missing filter geometry');
      const searchBottom = searchBox.y + searchBox.height;
      const statusBottom = statusBox.y + statusBox.height;
      assert(
        Math.abs(searchBottom - statusBottom) <= 3,
        `Filter bottoms differ: search=${searchBottom}, status=${statusBottom}`
      );
      assert(
        (await recipientOptionCount()) === 5,
        'Main recipient filter must have exactly five choices'
      );
    }
  );
  await check(
    'PT: primary recipient menu visibly exposes exactly five choices',
    async () => {
      const { trigger, items } = await dropdownItems(recipientFilterGroup);
      assert(
        (await items.count()) === 5,
        'Primary recipient menu must expose exactly five choices'
      );
      await shot('recipient-filter-open', null, { sequence: false });
      await trigger.click();
      await settle();
    }
  );
  await check(
    'PT: primary and contextual filters operate with the keyboard',
    async () => {
      const trigger = recipientFilterGroup.getByRole('button').first();
      await trigger.focus();
      await page.keyboard.press('Enter');
      const menu = page.getByRole('listbox', {
        name: await t('CAMPAIGN_MANAGEMENT.TABLE.STATUS'),
        exact: true,
      });
      assert(await menu.isVisible(), 'Enter did not open the custom menu');
      assert(
        (await menu.getByRole('option').count()) === 5,
        'Keyboard menu lost options'
      );
      await page.keyboard.press('End');
      assert(
        await menu
          .getByRole('option')
          .last()
          .evaluate(el => el === document.activeElement),
        'End did not focus last option'
      );
      await page.keyboard.press('Home');
      await page.keyboard.press('ArrowDown');
      await requestAfter('/recipients', () => page.keyboard.press('Enter'));
      assert(
        latest('/recipients').query.status === 'pending',
        'Keyboard selection differs from API filter'
      );
      assert(
        await trigger.evaluate(el => el === document.activeElement),
        'Selection did not restore trigger focus'
      );
      await page.keyboard.press('Space');
      assert(await menu.isVisible(), 'Space did not open the custom menu');
      await page.keyboard.press('Escape');
      assert(!(await menu.isVisible()), 'Escape did not close');
      assert(
        await trigger.evaluate(el => el === document.activeElement),
        'Escape lost trigger focus'
      );
      await page.keyboard.press('ArrowDown');
      await page.keyboard.press('Tab');
      assert(!(await menu.isVisible()), 'Tab did not leave dropdown');
      assert(
        !(await trigger.evaluate(el => el === document.activeElement)),
        'Tab trapped focus on trigger'
      );
      await trigger.focus();
      await page.keyboard.press('Enter');
      await page.keyboard.press('Home');
      await page.keyboard.press('ArrowDown');
      await page.keyboard.press('ArrowDown');
      await page.keyboard.press('ArrowDown');
      await requestAfter('/recipients', () => page.keyboard.press('Space'));
      const problemGroup = section.getByRole('group', {
        name: await ns('STATUS.attention'),
        exact: true,
      });
      const problemTrigger = problemGroup.getByRole('button').first();
      await problemTrigger.focus();
      await page.keyboard.press('ArrowDown');
      await page.keyboard.press('Home');
      await page.keyboard.press('ArrowDown');
      await page.keyboard.press('ArrowDown');
      await requestAfter('/recipients', () => page.keyboard.press('Enter'));
      assert(
        latest('/recipients').query.status === 'hard_bounced' &&
          latest('/recipients').query.problem === 'true',
        'Contextual keyboard filter is not exact'
      );
      await requestAfter('/recipients', () => selectRecipientStatus(''));
    }
  );
  await check(
    'PT: temporary, permanent and spam statuses have distinct visual meaning',
    async () => {
      const badgeInfo = async label => {
        const badge = section
          .locator('tbody td:nth-child(3) span[tabindex="0"]')
          .filter({ hasText: label })
          .first();
        assert(await badge.count(), `Badge missing: ${label}`);
        return badge.evaluate(element => ({
          background: getComputedStyle(element).backgroundColor,
          color: getComputedStyle(element).color,
          icon: [...element.querySelectorAll('span')]
            .map(node => node.className)
            .find(className => String(className).includes('i-lucide')),
        }));
      };
      const permanentLabel = (await ns('STATUS.permanent'))
        .split('—')
        .at(-1)
        .trim();
      const temporaryInfo = await badgeInfo(await ns('STATUS.temporary'));
      const permanentInfo = await badgeInfo(permanentLabel);
      assert(
        temporaryInfo.background !== permanentInfo.background &&
          temporaryInfo.icon !== permanentInfo.icon,
        JSON.stringify({ temporaryInfo, permanentInfo })
      );

      await requestAfter('/recipients', () =>
        selectRecipientStatus('attention')
      );
      await requestAfter('/recipients', () =>
        selectProblemStatus('complained')
      );
      const spamInfo = await badgeInfo(await ns('STATUS.complained'));
      assert(
        spamInfo.icon !== permanentInfo.icon &&
          spamInfo.icon !== temporaryInfo.icon,
        JSON.stringify({ spamInfo, permanentInfo, temporaryInfo })
      );
      await requestAfter('/recipients', () => selectRecipientStatus(''));
    }
  );
  await check('PT: three campaign choices survive selection', async () => {
    assert((await campaignOptionCount()) === 4, 'Expected all + three options');
    await requestAfter('/reports', () => selectCampaign('4362'));
    assert(
      (await campaignOptionCount()) === 4,
      'Options shrank after selecting sent campaign'
    );
    await requestAfter('/reports', () => selectCampaign('4361'));
  });
  await check(
    'PT: protection details stay secondary and preserve immutable pause snapshot',
    async () => {
      const panel = page.locator('section[aria-live]').first();
      const currentSection = page.locator('[data-section="CURRENT"]');
      const triggerSection = page.locator('[data-section="TRIGGER"]');
      assert(
        !(await currentSection.isVisible()) &&
          !(await triggerSection.isVisible()),
        'Technical detail opened by default'
      );
      await panel
        .getByRole('button', { name: await ns('DETAILS'), exact: true })
        .click();
      const currentText = await currentSection.innerText();
      const triggerText = await triggerSection.innerText();
      const date = await page.evaluate(
        value =>
          new Intl.DateTimeFormat('pt-BR', {
            dateStyle: 'medium',
            timeStyle: 'short',
          }).format(new Date(value)),
        current.evaluated_at
      );
      assert(
        currentText.includes('1.200') &&
          currentText.includes('1,5%') &&
          currentText.includes(date) &&
          triggerText.includes('800') &&
          triggerText.includes('8%'),
        'Current/trigger date/count/rate mismatch'
      );
      await panel
        .getByRole('button', { name: await ns('DETAILS'), exact: true })
        .click();
      assert(
        !(await currentSection.isVisible()),
        'Technical detail did not close'
      );
      return { currentText, triggerText };
    }
  );
  await check('PT: full long email copy and details', async () => {
    await section.locator('summary:visible').first().click();
    await section
      .getByRole('button', { name: await ns('COPY'), exact: true })
      .first()
      .click();
    assert(
      (await page.evaluate(() => navigator.clipboard.readText())) ===
        recipients[0].email,
      'Clipboard truncated'
    );
    await shot('long-email-details', section);
    await section.locator('summary:visible').first().click();
  });
  await check(
    'PT: status + search + problem combine; page 2; export identical filters',
    async () => {
      assert(
        (await recipientOptionCount()) === 5,
        'Main recipient filter must expose exactly five decisions'
      );
      await requestAfter('/recipients', () =>
        selectRecipientStatus('attention')
      );
      await requestAfter('/recipients', () =>
        selectProblemStatus('hard_bounced')
      );
      const search = section.getByRole('textbox', {
        name: await ns('SEARCH'),
        exact: true,
      });
      await requestAfter('/recipients', () => search.fill('qa-'));
      await requestAfter('/recipients', async () =>
        section
          .getByRole('button', {
            name: await t('CAMPAIGN_MANAGEMENT.RECIPIENTS.NEXT'),
            exact: true,
          })
          .click()
      );
      const query = latest('/recipients').query;
      assert(
        query.q === 'qa-' &&
          query.status === 'hard_bounced' &&
          query.problem === 'true' &&
          query.page === '2',
        JSON.stringify(query)
      );
      const downloadPromise = page.waitForEvent('download');
      await requestAfter('/export', async () =>
        section
          .getByRole('button', { name: await ns('EXPORT'), exact: true })
          .click()
      );
      const download = await downloadPromise;
      const downloadPath = resolve(output, 'filtered-recipients.csv');
      await download.saveAs(downloadPath);
      const exported = latest('/export').query;
      assert(
        exported.q === query.q &&
          exported.status === query.status &&
          exported.problem === query.problem &&
          !('page' in exported),
        JSON.stringify(exported)
      );
      const csv = await readFile(downloadPath, 'utf8');
      assert(
        csv.trim().split('\n').length === 11,
        'Export must include all 10 matching recipients, not current page'
      );
      await shot('recipients-filtered', section);
      await requestAfter('/recipients', () => search.fill('qa-0'));
      assert(
        latest('/recipients').query.page === '1',
        'Search change did not reset page'
      );
      return { table: query, export: exported };
    }
  );
  await check(
    'PT: refresh preserves active filters and 500 shows localized error',
    async () => {
      const before = latest('/recipients').query;
      state.recipientError = true;
      await requestAfter('/recipients', async () =>
        section
          .getByRole('button', { name: await ns('REFRESH'), exact: true })
          .click()
      );
      assert(
        JSON.stringify(latest('/recipients').query) === JSON.stringify(before),
        'Filters changed'
      );
      assert(
        (await section.getByRole('alert').innerText()) === (await ns('ERROR')),
        'Missing localized error'
      );
      assert(
        (await section.locator('tbody tr').count()) === 0,
        'Old rows shown as success after 500'
      );
      assert(
        !(await section.innerText()).includes(await ns('EMPTY')),
        '500 displayed successful empty state'
      );
      await shot('recipients-500', section);
      state.recipientError = false;
      await requestAfter('/recipients', async () =>
        section
          .getByRole('button', { name: await ns('REFRESH'), exact: true })
          .click()
      );
    }
  );
  await check(
    'PT: clear resets filters and Problems activates requires-attention',
    async () => {
      await requestAfter('/recipients', async () =>
        section
          .getByRole('button', { name: await ns('CLEAR'), exact: true })
          .click()
      );
      assert(
        latest('/recipients').query.q === '' &&
          latest('/recipients').query.page === '1' &&
          !latest('/recipients').query.status &&
          !latest('/recipients').query.problem,
        JSON.stringify(latest('/recipients').query)
      );
      await requestAfter('/recipients', async () =>
        page
          .getByRole('button', { name: await ns('PROBLEMS'), exact: true })
          .click()
      );
      assert(
        latest('/recipients').query.problem === 'true' &&
          (await recipientSelectionLabel()) === (await ns('STATUS.attention')),
        'Problems did not activate attention'
      );
      await requestAfter('/recipients', () => selectRecipientStatus(''));
    }
  );
  await check('PT: duplicate protection state is presented once', async () =>
    assert(
      (await page
        .locator('section[aria-live]')
        .first()
        .locator('span[tabindex="0"][title]')
        .count()) === 1,
      'Duplicate semantic pause badges'
    )
  );
  await check('PT: protected campaign hides resume and override', async () =>
    assert(
      (await page
        .getByRole('button', { name: await ns('RESUME'), exact: true })
        .count()) === 0 &&
        !/override|force send/i.test(await page.locator('body').innerText()),
      'Unsafe send control visible'
    )
  );
  await check(
    'PT: POST reevaluation 503 is localized and does not claim continued',
    async () => {
      await requestAfter('/reevaluate', async () =>
        page
          .getByRole('button', { name: await ns('REEVALUATE'), exact: true })
          .click()
      );
      assert(
        (await page.getByRole('alert').innerText()) === (await ns('ERROR')),
        'Missing safe localized action error'
      );
      assert(
        !(await page.locator('body').innerText()).includes(
          'SYNTHETIC_PRIVATE_MARKER'
        ),
        'Provider diagnostic leaked'
      );
      await shot(
        'reevaluate-503',
        page.locator('section[aria-live]').first().locator('..')
      );
    }
  );
  await check('PT: import issues loaded through real API adapter', async () => {
    await requestAfter('/import_issues', async () =>
      page
        .getByRole('button', { name: await ns('ISSUES'), exact: true })
        .click()
    );
    const issuesSection = page.locator('section').filter({
      has: page.getByRole('heading', {
        name: await ns('ISSUES'),
        exact: true,
      }),
    });
    assert(
      (await issuesSection.locator('li').count()) === 4,
      'Expected four issue rows'
    );
    await shot('import-issues', issuesSection);
  });
  await check(
    'PT: manual capability permits resume with a truthful title',
    async () => {
      await requestAfter('/reports', () => selectCampaign('4363'));
      assert(
        await page
          .getByRole('button', { name: await ns('RESUME'), exact: true })
          .isVisible(),
        'Legitimate manual resume missing'
      );
      assert(
        (await page.locator('section[aria-live] h3').first().innerText()) ===
          (await ns('STATUS.manual')),
        'Manual pause mislabeled as protection'
      );
      await shot(
        'manual-protection',
        page.locator('section[aria-live]').first()
      );
    }
  );
  await check(
    'PT: main report 500 preserves selected campaign and hides success metrics',
    async () => {
      state.reportError = true;
      await requestAfter('/reports', async () =>
        page
          .getByRole('button', { name: await ns('REFRESH'), exact: true })
          .first()
          .click()
      );
      assert(
        (await campaignSelectionLabel()).includes('QA — Pausa manual'),
        'Selection lost'
      );
      assert(
        await page
          .getByText(await t('CAMPAIGN_MANAGEMENT.ERROR'), { exact: true })
          .isVisible(),
        'Main report failure absent'
      );
      assert(
        !(await page.locator('[data-section="CURRENT"]').isVisible()),
        'Main successful report remains visible'
      );
      await shot('report-500');
    }
  );
  await desktop.inspect();
  await check('PT: interaction labels remain localized without fallback', () =>
    assert(
      !desktop.record.runtime.missing.length,
      desktop.record.runtime.missing.join(', ')
    )
  );
  await desktop.context.close();
  for (const [name, options] of [
    ['pt-dark', { theme: 'dark' }],
    ['pt-readonly', { role: 'readonly' }],
    ['pt-mixed-evidence', { scenario: 'mixed' }],
    ['ar-rtl', { locale: 'ar', viewport: { width: 1440, height: 900 } }],
    ['pt-mobile', { viewport: { width: 390, height: 844 } }],
    [
      'pt-sidebar-narrow',
      { viewport: { width: 1024, height: 900 }, contentWidth: 742 },
    ],
    ['de-desktop', { locale: 'de' }],
    ['en-desktop', { locale: 'en' }],
    ['pt-unknown', { scenario: 'unknown' }],
    ['pt-direct', { scenario: 'direct' }],
    ['pt-provider', { scenario: 'provider' }],
    ['pt-manual-provider', { scenario: 'provider', campaign: 4363 }],
    ['pt-unfresh', { scenario: 'unfresh' }],
    [
      'pt-mixed-denominator',
      { scenario: 'mixed-denominator', campaign: false },
    ],
    ['pt-import-populations', { scenario: 'import-populations' }],
    [
      'ar-import-mobile',
      {
        scenario: 'import-populations',
        locale: 'ar',
        viewport: { width: 390, height: 844 },
      },
    ],
  ]) {
    const screen = await openScreen(name, options);
    await smoke(screen);
    await screen.shot(
      'protection',
      screen.page.locator('section[aria-live]').first()
    );
    await screen.shot('recipients', screen.section);
    if (name === 'pt-readonly') {
      await check(
        'Read-only: real permission composable hides write and export actions',
        async () => {
          for (const key of ['RESUME', 'REEVALUATE', 'RECHECK', 'EXPORT']) {
            assert(
              (await screen.page
                .getByRole('button', {
                  name: await screen.ns(key),
                  exact: true,
                })
                .count()) === 0,
              `Unauthorized action ${key}`
            );
          }
          assert(
            await screen.section.isVisible(),
            'Read-only recipient list is missing'
          );
        }
      );
    }
    if (name === 'pt-mixed-evidence') {
      await check(
        'Mixed: collapsed evidence preserves both exact delivery populations',
        async () => {
          await screen.requestAfter('/reports', () =>
            screen.selectCampaign('')
          );
          const toggle = screen.page.locator('[data-delivery-evidence-toggle]');
          const evidence = screen.page.locator('[data-delivery-evidence]');
          assert(
            !(await evidence.isVisible()),
            'Evidence should start collapsed'
          );
          await toggle.click();
          const payload = screen.latest('/reports').response.json.payload;
          assert(
            payload?.summary?.delivery_evidence,
            'Missing synthetic response evidence'
          );
          assert(
            payload.summary.delivery_evidence.provider_confirmed > 0 &&
              payload.summary.delivery_evidence.direct_acceptance_only > 0,
            'Mixed gate must exercise both positive populations'
          );
          const counts = await evidence.locator('dd').allTextContents();
          const format = value => new Intl.NumberFormat('pt-BR').format(value);
          assert(
            counts[0].trim() ===
              format(payload.summary.delivery_evidence.provider_confirmed),
            'Recipient-server acceptance count was lost'
          );
          assert(
            counts[1].trim() ===
              format(payload.summary.delivery_evidence.direct_acceptance_only),
            'Sending-service acceptance count was lost'
          );
          assert(
            !/\b(?:SES|Amazon|AWS)\b/.test(await evidence.innerText()),
            'Infrastructure jargon leaked into details'
          );
          await screen.shot('delivery-evidence', evidence);
          await toggle.click();
        }
      );
    }
    if (name === 'pt-direct') {
      await check(
        'Direct: sending-service acceptance with unchanged delivered query',
        async () => {
          await screen.requestAfter('/recipients', () =>
            screen.selectRecipientStatus('delivered')
          );
          const label = await screen.ns('STATUS.accepted_service');
          assert(
            (await screen.recipientSelectionLabel()) === label,
            'Direct filter claims recipient delivery'
          );
          const badges = await screen.section
            .locator('tbody tr td:nth-child(3)')
            .allTextContents();
          assert(
            badges.length > 0 && badges.every(text => text.trim() === label),
            'Direct badge claims recipient delivery'
          );
          assert(
            results.requests
              .filter(r => r.screen === name && r.path.endsWith('/recipients'))
              .at(-1).query.status === 'delivered',
            'Machine filter changed'
          );
          const deliveryHint = await screen.ns('DELIVERY_HINT');
          assert(
            await screen.section
              .locator('[aria-label]')
              .evaluateAll(
                (nodes, hint) =>
                  nodes.some(node =>
                    node.getAttribute('aria-label')?.includes(hint)
                  ),
                deliveryHint
              ),
            'Missing acceptance caveat'
          );
          await screen.shot('direct-delivered', screen.section);
        }
      );
    }
    if (name === 'pt-dark')
      await check('Dark: rendered theme changes badge colors', () => {
        assert(screen.record.layout.dark, 'Dark class not active');
        const light = results.screens[0].initialLayout.badges[0];
        const dark = screen.record.layout.badges[0];
        assert(
          light.background !== dark.background && light.color !== dark.color,
          'Dark theme has same computed colors'
        );
        return { light, dark };
      });
    if (name === 'ar-rtl') {
      await check(
        'Arabic: RTL layout with localized status and interface controls',
        async () => {
          assert(screen.record.layout.direction === 'rtl', 'RTL inactive');
          assert(
            screen.record.layout.badges.some(b =>
              /[\u0600-\u06ff]/.test(b.text)
            ),
            'Arabic badge absent'
          );
          for (const label of [
            await screen.ns('REFRESH'),
            await screen.ns('EXPORT'),
            await screen.ns('CLEAR'),
          ]) {
            assert(
              /[\u0600-\u06ff]/.test(label),
              `Untranslated label: ${label}`
            );
            assert(
              (await screen.page
                .getByRole('button', { name: label, exact: true })
                .count()) > 0,
              `Localized control missing: ${label}`
            );
          }
          const statusTrigger = screen.section
            .getByRole('group', {
              name: await screen.t('CAMPAIGN_MANAGEMENT.TABLE.STATUS'),
              exact: true,
            })
            .getByRole('button')
            .first();
          assert(
            /[\u0600-\u06ff]/.test(await statusTrigger.innerText()),
            'Status dropdown label is not localized'
          );
        }
      );
      await check(
        'Arabic: table and open detail email isolation preserves RTL labels',
        () => rtlEmails(screen)
      );
    }
    if (name === 'pt-sidebar-narrow') {
      await screen.requestAfter('/recipients', () =>
        screen.selectRecipientStatus('attention')
      );
      await check(
        'Narrow dashboard: contextual filters wrap inside sidebar-constrained content',
        async () => {
          const sectionBox = await screen.section.boundingBox();
          assert(sectionBox, 'Recipient section has no geometry');
          const filterBar = screen.section.locator(
            '[data-email-recipient-filters]'
          );
          const groups = filterBar.getByRole('group');
          const boxes = await groups.evaluateAll(nodes =>
            nodes.map(node => {
              const rect = node.getBoundingClientRect();
              return {
                left: rect.left,
                right: rect.right,
                width: rect.width,
              };
            })
          );
          assert(
            boxes.every(
              box =>
                box.left >= sectionBox.x - 1 &&
                box.right <= sectionBox.x + sectionBox.width + 1
            ),
            JSON.stringify({ sectionBox, boxes })
          );
          const overflow = await filterBar.evaluate(element => ({
            clientWidth: element.clientWidth,
            scrollWidth: element.scrollWidth,
          }));
          assert(
            overflow.scrollWidth <= overflow.clientWidth + 1,
            JSON.stringify(overflow)
          );
          return { sectionBox, boxes, overflow };
        }
      );
      await screen.shot('attention-filters', screen.section);
    }
    if (name === 'pt-mobile') {
      await check(
        'Mobile: full-width search and readable input label',
        async () => {
          const search = screen.page.getByRole('textbox', {
            name: await screen.ns('SEARCH'),
            exact: true,
          });
          const geometry = await search.evaluate(input => {
            const label = input.labels?.[0];
            return {
              width: input.getBoundingClientRect().width,
              labelHeight: label?.getBoundingClientRect().height,
              lineHeight: label
                ? Number.parseFloat(getComputedStyle(label).lineHeight)
                : 0,
            };
          });
          assert(
            geometry.width >= 220,
            `Search collapsed to ${geometry.width}px`
          );
          assert(
            geometry.lineHeight > 0 &&
              geometry.labelHeight <= geometry.lineHeight * 2.1,
            'Search label wraps into a narrow column'
          );
          const statusGroup = screen.section.getByRole('group', {
            name: await screen.t('CAMPAIGN_MANAGEMENT.TABLE.STATUS'),
            exact: true,
          });
          const statusBox = await statusGroup.boundingBox();
          assert(
            statusBox && statusBox.width >= 220,
            `Status filter collapsed to ${statusBox?.width}px`
          );
          return { ...geometry, statusWidth: statusBox.width };
        }
      );
      await check(
        'Mobile: readable recipient cards without horizontal scroll',
        () => mobileTable(screen)
      );
      await check(
        'Mobile: clicks by link render as cards without clipping',
        async () => {
          const clicksSection = screen.page.locator('section').filter({
            has: screen.page.getByRole('heading', {
              name: await screen.t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TITLE'),
              exact: true,
            }),
          });
          const cards = clicksSection.locator('[data-click-card]');
          assert((await cards.count()) > 0, 'Mobile click cards are missing');
          assert(
            !(await clicksSection.locator('table').isVisible()),
            'Desktop click table is still visible on mobile'
          );
          const geometry = await cards.evaluateAll(elements =>
            elements.map(element => {
              const rect = element.getBoundingClientRect();
              const parent = element.parentElement.getBoundingClientRect();
              return {
                left: rect.left,
                right: rect.right,
                parentLeft: parent.left,
                parentRight: parent.right,
                scrollWidth: element.scrollWidth,
                clientWidth: element.clientWidth,
              };
            })
          );
          assert(
            geometry.every(
              item =>
                item.left >= item.parentLeft - 1 &&
                item.right <= item.parentRight + 1 &&
                item.scrollWidth <= item.clientWidth + 1
            ),
            JSON.stringify(geometry)
          );
          return geometry;
        }
      );
      const mobileClicksSection = screen.page.locator('section').filter({
        has: screen.page.getByRole('heading', {
          name: await screen.t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TITLE'),
          exact: true,
        }),
      });
      await screen.shot('mobile-click-cards', mobileClicksSection);
      await check(
        'Mobile: 100% exposed buttons and each detail copy reachable by keyboard',
        () => keyboardCoverage(screen)
      );
    }
    if (
      [
        'pt-provider',
        'pt-manual-provider',
        'pt-unfresh',
        'pt-unknown',
      ].includes(name)
    )
      await check(`${name}: no unsafe resume`, async () =>
        assert(
          (await screen.page
            .getByRole('button', {
              name: await screen.ns('RESUME'),
              exact: true,
            })
            .count()) === 0,
          'Unsafe resume visible'
        )
      );
    if (name === 'pt-manual-provider')
      await check(
        'Manual + provider: account block takes explanatory priority',
        async () => {
          const panel = screen.page.locator('section[aria-live]').first();
          assert(
            (await panel.locator('h3').innerText()) ===
              (await screen.ns('STATUS.paused_unknown')),
            'Provider block mislabeled as manual-only'
          );
          assert(
            (await panel.innerText()).includes(
              await screen.ns('REASON.provider')
            ) &&
              !(await panel.innerText()).includes(
                await screen.ns('REASON.manual')
              ),
            'Actual provider restriction not prioritized'
          );
        }
      );
    if (name === 'pt-unknown')
      await check(
        'Unknown: missing evaluation and counts never render fabricated healthy/zero metrics',
        async () => {
          const panel = await screen.page
            .locator('section[aria-live]')
            .first()
            .innerText();
          assert(
            panel.includes(await screen.ns('STATUS.paused_unknown')) &&
              !panel.includes(await screen.ns('STATUS.healthy')) &&
              panel.includes(await screen.ns('REASON.unknown')),
            'Paused campaign with missing evaluation was not kept safely paused'
          );
          assert(
            !panel.includes('—'),
            'Unknown state exposed placeholder dashes'
          );
          const currentDetails = screen.page.locator(
            '[data-section="CURRENT"]'
          );
          assert(
            (await currentDetails.count()) === 0 ||
              !(await currentDetails.isVisible()),
            'Unknown technical metrics exposed by default'
          );
          assert(
            (await screen.page.locator('body').innerText()).includes(
              await screen.ns('PENDING_COUNTS')
            ),
            'Incomplete preflight not declared'
          );
        }
      );
    await screen.inspect();
    await check(
      `${name}: interaction labels remain localized without fallback`,
      () =>
        assert(
          !screen.record.runtime.missing.length,
          screen.record.runtime.missing.join(', ')
        )
    );
    await screen.context.close();
    await save();
  }
  await check(
    'All screens have no unhandled runtime errors after interactions',
    () =>
      assert(
        results.screens.every(
          screen =>
            !screen.pageErrors.length && !screen.runtime?.vueErrors.length
        ),
        'Unhandled error after initial smoke'
      )
  );
  await check('All HTTP fixture routes match intended account scope', () =>
    assert(
      results.requests.every(
        r =>
          r.path.startsWith('/api/v1/accounts/436/') &&
          r.response.status !== 404
      ),
      'Unmatched API or missing account scope'
    )
  );
} catch (error) {
  results.fatal = { message: error.message, stack: error.stack };
  console.error(error);
} finally {
  if (browser) await browser.close();
  if (server) {
    await server.close();
    results.serverStoppedAt = new Date().toISOString();
  } else results.serverListening = false;
  await save();
  console.log(
    JSON.stringify({
      counts: results.counts,
      fatal: results.fatal,
      artifact: resolve(output, 'results.json'),
    })
  );
  process.exitCode = results.fatal || results.counts.failed ? 1 : 0;
}
