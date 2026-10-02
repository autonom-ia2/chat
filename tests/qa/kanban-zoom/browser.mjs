// Real-browser regression against the dedicated local Rails/Vite QA runtime.
// No mocked CRM handlers: drag-and-drop must receive a successful server response.
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import {
  chromium,
  firefox,
  webkit,
} from '../../playwright/node_modules/playwright/index.mjs';

const base = process.env.KANBAN_QA_URL || 'http://127.0.0.1:3839';
const url = new URL(base);
assert(
  ['127.0.0.1', 'localhost'].includes(url.hostname),
  'Only the disposable local QA runtime is permitted'
);
const fixture = JSON.parse(await readFile('.codex/839/fixture.json', 'utf8'));
const engine = process.env.KANBAN_QA_BROWSER || 'chromium';
assert(['chromium', 'firefox', 'webkit'].includes(engine));
const browser = await { chromium, firefox, webkit }[engine].launch({
  timeout: 30000,
});
const context = await browser.newContext({
  viewport: { width: 1600, height: 1000 },
  locale: 'pt-BR',
  hasTouch: engine === 'chromium',
});
const page = await context.newPage();
const errors = [];
const requests = [];
const checks = [];
page.on('pageerror', error => errors.push(error.message));
page.on('request', request => {
  if (request.url().includes('/api/') && request.url().includes('/crm/'))
    requests.push({ url: request.url(), method: request.method() });
});
const output = `.codex/839/browser-${engine}`;
await mkdir(output, { recursive: true });
const record = (name, details = {}) => {
  checks.push({ name, status: 'passed', ...details });
  console.log('PASS', name);
};
const closeEnough = (actual, expected, label, tolerance = 1) =>
  assert(
    Math.abs(actual - expected) <= tolerance,
    `${label}: ${actual} != ${expected}`
  );
const board = () => page.locator('[data-kanban-board]');
const trigger = () => page.locator('[data-kanban-zoom] button');
const panel = () => page.getByRole('dialog', { name: 'Zoom do Kanban' });
const stage = id => page.locator(`[data-stage-id="${id}"]`);
const zoom = async (value, keepOpen = false) => {
  await trigger().click();
  await panel().waitFor();
  const preset = [80, 90, 100, 110, 120].reduce(
    (best, next) =>
      Math.abs(next - value) < Math.abs(best - value) ? next : best,
    100
  );
  await panel()
    .getByRole('button', { name: `${preset}%`, exact: true })
    .click();
  const button = panel().getByRole('button', {
    name: value < preset ? 'Diminuir zoom em 1%' : 'Aumentar zoom em 1%',
    exact: true,
  });
  for (let i = 0; i < Math.abs(value - preset); i += 1) await button.click();
  assert.equal(
    (await panel().locator('output').innerText()).trim(),
    `${value}%`
  );
  assert.equal((await trigger().innerText()).trim(), `${value}%`);
  const active = panel().locator('[aria-pressed="true"]');
  assert.equal(
    await active.count(),
    [80, 90, 100, 110, 120].includes(value) ? 1 : 0
  );
  if (!keepOpen) await page.keyboard.press('Escape');
};
const visit = async (account = fixture.account_id, query = '') => {
  await page.goto(`${base}/app/accounts/${account}/crm${query}`);
  await board().waitFor();
  await page.locator('[data-stage-id]').first().waitFor();
  assert.equal(
    await page.locator('pre').filter({ hasText: 'Error: Item slot' }).count(),
    0
  );
};
const layout = () =>
  page.evaluate(() => {
    const rect = selector => {
      const element = document.querySelector(selector);
      const bounds = element.getBoundingClientRect();
      return {
        x: bounds.x,
        y: bounds.y,
        width: bounds.width,
        height: bounds.height,
      };
    };
    return {
      header: rect('main main > header'),
      trigger: rect('[data-kanban-zoom]'),
      board: rect('[data-kanban-board]'),
      stage: rect('[data-stage-id]'),
      card: rect('[data-card-id]'),
    };
  });
const moveResponse = id =>
  page.waitForResponse(
    response =>
      response.url().endsWith(`/crm/cards/${id}/move`) &&
      response.request().method() === 'POST',
    { timeout: 10000 }
  );
const confirmMove = async (response, id, destination) => {
  assert.equal(response.status(), 200);
  const body = await response.json();
  assert.equal(Number(body.payload.stage_id), Number(destination));
  await stage(destination).locator(`[data-card-id="${id}"]`).waitFor();
  await page.reload();
  await board().waitFor();
  await stage(destination).locator(`[data-card-id="${id}"]`).waitFor();
};

try {
  await page.goto(`${base}/app/login`);
  await page.locator('input[name="email_address"]').fill(fixture.email);
  await page.locator('input[name="password"]').fill(fixture.password);
  await page.locator('input[name="password"]').press('Enter');
  await page.waitForURL(current => current.pathname.includes('/accounts/'));
  await visit();
  await zoom(100, true);
  const buttonBorders = await page
    .locator('[data-kanban-zoom] button, section[role="dialog"] button')
    .evaluateAll(nodes =>
      nodes.map(element => {
        const style = getComputedStyle(element);
        return { width: style.borderTopWidth, style: style.borderTopStyle };
      })
    );
  assert.equal(buttonBorders.length, 8);
  buttonBorders.forEach(border =>
    assert.deepEqual(border, { width: '1px', style: 'solid' })
  );
  record(
    'Reference borders visible on the trigger, step controls and all presets'
  );
  await page.keyboard.press('Escape');
  const reference = await layout();
  record('Authenticated real application and synthetic CRM fixtures');

  for (const value of [70, 80, 87, 90, 100, 110, 117, 120, 130]) {
    await page.waitForTimeout(200);
    const requestCount = requests.length;
    await zoom(value);
    assert.equal(
      requests.length,
      requestCount,
      'Zoom must not reload CRM data'
    );
    const current = await layout();
    for (const part of ['header', 'trigger', 'board']) {
      for (const dimension of ['x', 'y', 'width', 'height'])
        closeEnough(
          current[part][dimension],
          reference[part][dimension],
          `${part}.${dimension} at ${value}`
        );
    }
    closeEnough(
      current.stage.width,
      (reference.stage.width * value) / 100,
      `Column width at ${value}`
    );
    closeEnough(
      current.card.width,
      (reference.card.width * value) / 100,
      `Card width at ${value}`
    );
    await board().evaluate(element => {
      element.scrollLeft = element.scrollWidth;
    });
    const lastColumn = await page
      .locator('[data-stage-id]')
      .last()
      .boundingBox();
    const viewport = await board().boundingBox();
    assert(
      lastColumn.x + lastColumn.width <= viewport.x + viewport.width + 1,
      'Last column remains reachable'
    );
    await board().evaluate(element => {
      element.scrollLeft = 0;
    });
    const firstColumn = await page
      .locator('[data-stage-id]')
      .first()
      .boundingBox();
    assert(firstColumn.x >= viewport.x, 'First column remains reachable');
    const list = stage(fixture.stage_ids[0]).locator(':scope > div');
    await list.evaluate(element => {
      element.scrollTop = element.scrollHeight;
    });
    const lastCard = await list.locator('[data-card-id]').last().boundingBox();
    const listRect = await list.boundingBox();
    assert(
      lastCard.y + lastCard.height <= listRect.y + listRect.height + 1,
      'Last loaded card remains reachable'
    );
    await list.evaluate(element => {
      element.scrollTop = 0;
    });
    await page.screenshot({ path: `${output}/zoom-${value}.png` });
    record(
      `Layout, exact zoom, presets, no CRM requests and both scroll axes at ${value}%`
    );

    const source = stage(fixture.stage_ids[0])
      .locator('[data-card-id]')
      .first();
    const id = Number(await source.getAttribute('data-card-id'));
    const destination = fixture.stage_ids[1];
    const responsePromise = moveResponse(id);
    const sourceRect = await source.boundingBox();
    const targetRect = await stage(destination)
      .locator(':scope > div')
      .boundingBox();
    await page.mouse.move(sourceRect.x + 40, sourceRect.y + 24);
    await page.mouse.down();
    await page.mouse.move(sourceRect.x + 65, sourceRect.y + 32, { steps: 8 });
    const preview = page.locator('body > .crm-kanban-drag-preview');
    await preview.waitFor();
    const previewRect = await preview.boundingBox();
    closeEnough(previewRect.width, sourceRect.width, 'Mouse preview width');
    closeEnough(previewRect.height, sourceRect.height, 'Mouse preview height');
    await page.mouse.move(targetRect.x + 60, targetRect.y + 55, { steps: 15 });
    await page.waitForTimeout(200);
    await page.mouse.up();
    await preview.waitFor({ state: 'detached' });
    await confirmMove(await responsePromise, id, destination);
    record(
      `Mouse drag to adjacent stage and persisted server destination at ${value}%`
    );
  }

  await zoom(70, true);
  assert(
    await panel()
      .getByRole('button', { name: 'Diminuir zoom em 1%' })
      .isDisabled()
  );
  assert(
    !(await panel()
      .getByRole('button', { name: 'Aumentar zoom em 1%' })
      .isDisabled())
  );
  await page.keyboard.press('Escape');
  await zoom(130, true);
  assert(
    await panel()
      .getByRole('button', { name: 'Aumentar zoom em 1%' })
      .isDisabled()
  );
  await page.keyboard.press('Escape');
  record('Inclusive 70/130 limits and disabled controls');

  if (engine === 'chromium') {
    const cdp = await context.newCDPSession(page);
    for (const value of [70, 87, 100, 117, 130]) {
      await zoom(value);
      const source = stage(fixture.stage_ids[0])
        .locator('[data-card-id]')
        .first();
      const id = Number(await source.getAttribute('data-card-id'));
      const original = await source.boundingBox();
      const x = original.x + original.width / 2;
      const y = original.y + 18;
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchStart',
        touchPoints: [{ x, y }],
      });
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [{ x: x + 30, y: y + 30 }],
      });
      await page.locator('body > .crm-kanban-drag-preview').waitFor();
      const ghost = page.locator('body > .crm-kanban-drag-preview');
      const first = await ghost.boundingBox();
      const child = await ghost.locator(':scope > div').boundingBox();
      closeEnough(first.width, original.width, 'Touch preview width');
      closeEnough(first.height, original.height, 'Touch preview height');
      closeEnough(child.width, original.width, 'Touch preview child width');
      closeEnough(
        child.height,
        original.height,
        'Touch preview child height',
        2
      );
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [{ x: x + 60, y: y + 50 }],
      });
      const moved = await ghost.boundingBox();
      closeEnough(
        moved.x - original.x,
        60,
        'Touch preview horizontal tracking'
      );
      closeEnough(moved.y - original.y, 50, 'Touch preview vertical tracking');
      const destination = fixture.stage_ids[2];
      const target = await stage(destination)
        .locator(':scope > div')
        .boundingBox();
      const responsePromise = moveResponse(id);
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [{ x: target.x + 55, y: target.y + 80 }],
      });
      await page.waitForTimeout(250);
      await page.screenshot({ path: `${output}/touch-${value}.png` });
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchEnd',
        touchPoints: [],
      });
      await confirmMove(await responsePromise, id, destination);
      record(
        `Real touch preview geometry, finger tracking, drop and persistence at ${value}%`
      );
    }
  }

  await zoom(87);
  await page.reload();
  await board().waitFor();
  assert.equal((await trigger().innerText()).trim(), '87%');
  await page
    .locator('main main > header')
    .getByRole('button', { name: 'Lista', exact: true })
    .click();
  await trigger().waitFor({ state: 'detached' });
  assert.equal(await board().count(), 0);
  await page
    .locator('main main > header')
    .getByRole('button', { name: 'Kanban', exact: true })
    .click();
  await board().waitFor();
  assert.equal((await trigger().innerText()).trim(), '87%');
  await page
    .locator('main main > header')
    .getByRole('button', { name: 'Calendário', exact: true })
    .click();
  await trigger().waitFor({ state: 'detached' });
  assert.equal(await board().count(), 0);
  await page
    .locator('main main > header')
    .getByRole('button', { name: 'Kanban', exact: true })
    .click();
  await board().waitFor();
  assert.equal((await trigger().innerText()).trim(), '87%');
  record(
    '87% restored on reload and through Lista/Calendário without scaling either view'
  );

  await page.getByRole('combobox').first().click();
  await page.getByRole('option', { name: 'Outro funil', exact: true }).click();
  await page.getByRole('heading', { name: 'Entrada', exact: true }).waitFor();
  assert.equal((await trigger().innerText()).trim(), '87%');
  await page.getByRole('combobox').first().click();
  await page
    .getByRole('option', { name: 'Email Comercial', exact: true })
    .click();
  await stage(fixture.stage_ids[0]).waitFor();
  record('Same exact preference across funnels');

  await visit(fixture.other_account_id);
  assert.equal((await trigger().innerText()).trim(), '100%');
  await zoom(117);
  await visit();
  assert.equal((await trigger().innerText()).trim(), '87%');
  record('Account preference isolation and restored original account');

  await zoom(93, true);
  await panel().getByRole('button', { name: 'Aumentar zoom em 1%' }).focus();
  await page.keyboard.press('Enter');
  assert.equal((await panel().locator('output').innerText()).trim(), '94%');
  await page.keyboard.press('Escape');
  assert(
    await trigger().evaluate(element => element === document.activeElement)
  );
  await trigger().click();
  await page.getByRole('heading', { name: 'CRM Kanban', exact: true }).click();
  await panel().waitFor({ state: 'detached' });
  record('Keyboard increment, Escape, restored focus and outside click');

  for (const viewport of [
    { width: 1366, height: 768 },
    { width: 1024, height: 768 },
    { width: 390, height: 844 },
  ]) {
    await page.setViewportSize(viewport);
    await zoom(90, true);
    const rect = await panel().boundingBox();
    assert(
      rect.x >= 0 && rect.x + rect.width <= viewport.width + 1,
      'Popover fits viewport horizontally'
    );
    assert(
      rect.y >= 0 && rect.y + rect.height <= viewport.height + 1,
      'Popover fits viewport vertically'
    );
    await page.screenshot({ path: `${output}/viewport-${viewport.width}.png` });
    await page.keyboard.press('Escape');
    record(
      `Responsive toolbar and usable popover at ${viewport.width}×${viewport.height}`
    );
  }
  await page.setViewportSize({ width: 1600, height: 1000 });
  await zoom(90, true);
  await page.screenshot({ path: `${output}/approved-popover.png` });
  await panel().screenshot({ path: `${output}/popover-detail.png` });
  assert.deepEqual(errors, [], 'No browser runtime errors');
  record('No browser runtime errors');
} catch (error) {
  checks.push({ name: 'Failure', status: 'failed', message: error.message });
  await page.screenshot({ path: `${output}/failure.png` }).catch(() => {});
  console.error(error);
  process.exitCode = 1;
} finally {
  await writeFile(
    `${output}/report.json`,
    JSON.stringify({ engine, checks, errors }, null, 2)
  );
  await browser.close();
}
