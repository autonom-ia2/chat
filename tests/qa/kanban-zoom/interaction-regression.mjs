// Additional local regression: automatic column ordering, edge auto-scroll,
// unscaled drawers, existing search/filter controls and a real browser restart.
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { chromium } from '../../playwright/node_modules/playwright/index.mjs';

const base = 'http://127.0.0.1:3839';
const fixture = JSON.parse(await readFile('.codex/839/fixture.json', 'utf8'));
const directory = '.codex/839/interaction-regression';
await mkdir(directory, { recursive: true });
const checks = [];
const errors = [];
const record = name => {
  checks.push({ name, status: 'passed' });
  console.log('PASS', name);
};
let context = await chromium.launchPersistentContext(
  `${directory}/browser-profile`,
  {
    headless: true,
    viewport: { width: 1600, height: 1000 },
    locale: 'pt-BR',
  }
);
let page = await context.newPage();
const watchErrors = () =>
  page.on('pageerror', error => errors.push(error.message));
watchErrors();
const board = () => page.locator('[data-kanban-board]');
const trigger = () => page.locator('[data-kanban-zoom] button');
const stage = id => page.locator(`[data-stage-id="${id}"]`);
const visit = async () => {
  await page.goto(`${base}/app/accounts/${fixture.account_id}/crm`);
  await board().waitFor();
  await page.locator('[data-card-id]').first().waitFor();
};
const zoom = async value => {
  await trigger().click();
  const dialog = page.getByRole('dialog', { name: 'Zoom do Kanban' });
  await dialog.getByRole('button', { name: '100%', exact: true }).click();
  const button = dialog.getByRole('button', {
    name: value < 100 ? 'Diminuir zoom em 1%' : 'Aumentar zoom em 1%',
  });
  for (let i = 0; i < Math.abs(value - 100); i += 1) await button.click();
  await page.keyboard.press('Escape');
  assert.equal(await trigger().innerText(), `${value}%`);
};
const closeDrawer = async locator => {
  await locator.getByRole('button', { name: 'Fechar', exact: true }).click();
  await locator.waitFor({ state: 'detached' });
};
const assertUnscaled = async locator => {
  const result = await locator.evaluate(element => {
    const rect = element.getBoundingClientRect();
    return {
      width: rect.width,
      height: rect.height,
      insideBoard: Boolean(element.closest('[data-kanban-board]')),
      zoom: getComputedStyle(element).zoom,
    };
  });
  assert.equal(result.insideBoard, false);
  assert.equal(Number(result.zoom), 1);
  assert.equal(result.width, 640);
  assert.equal(result.height, 1000);
};

try {
  await page.goto(`${base}/app/accounts/${fixture.account_id}/crm`);
  await page
    .locator('[data-kanban-board], input[name="email_address"]')
    .first()
    .waitFor();
  if (await page.locator('input[name="email_address"]').isVisible()) {
    await page.locator('input[name="email_address"]').fill(fixture.email);
    await page.locator('input[name="password"]').fill(fixture.password);
    await page.locator('input[name="password"]').press('Enter');
    await page.waitForURL(url => url.pathname.includes('/accounts/'));
  }
  await visit();

  for (const value of [70, 80, 87, 90, 100, 110, 117, 120, 130]) {
    await zoom(value);
    const cards = stage(fixture.stage_ids[0]).locator('[data-card-id]');
    const before = await cards.evaluateAll(elements =>
      elements.map(element => element.dataset.cardId)
    );
    let moves = 0;
    const onRequest = request => {
      if (request.url().endsWith('/move') && request.method() === 'POST')
        moves += 1;
    };
    page.on('request', onRequest);
    await cards.first().dragTo(cards.nth(1));
    const after = await cards.evaluateAll(elements =>
      elements.map(element => element.dataset.cardId)
    );
    assert.deepEqual(
      after,
      before,
      'Automatic in-column ordering must not become manual'
    );
    assert.equal(moves, 0, 'In-column gesture must not mutate the card stage');
    page.off('request', onRequest);
    const firstCard = await cards.first().boundingBox();
    const secondCard = await cards.nth(1).boundingBox();
    await page.mouse.move(firstCard.x + 65, firstCard.y + 26);
    await page.mouse.down();
    await page.mouse.move(secondCard.x + 65, secondCard.y + 26, { steps: 14 });
    await page.locator('body > .crm-kanban-drag-preview').waitFor();
    await page.mouse.move(firstCard.x + 65, firstCard.y + 26, { steps: 14 });
    await page.waitForTimeout(200);
    await page.mouse.up();
    await page
      .locator('body > .crm-kanban-drag-preview')
      .waitFor({ state: 'detached' });
    assert.equal(
      await page.locator('[data-crm-card-drawer]').count(),
      0,
      'Returning from a drag must not open the card drawer'
    );
    record(
      `Automatic in-column ordering and no accidental click after return drag at ${value}%`
    );

    await page
      .getByRole('button', { name: 'Mais filtros', exact: true })
      .click();
    const filter = page.locator('[data-crm-kanban-filters-drawer]');
    await filter.waitFor();
    await page.waitForTimeout(250);
    await assertUnscaled(filter);
    await closeDrawer(filter);
    await page
      .getByRole('button', { name: 'Nova oportunidade', exact: true })
      .click();
    const drawer = page.locator('[data-crm-card-drawer]');
    await drawer.waitFor();
    await page.waitForTimeout(250);
    await assertUnscaled(drawer);
    await closeDrawer(drawer);
    await cards.first().click();
    await drawer.waitFor();
    await page.waitForTimeout(250);
    await assertUnscaled(drawer);
    await page.screenshot({ path: `${directory}/card-drawer-${value}.png` });
    await closeDrawer(drawer);
    record(
      `Filters, new opportunity and existing card drawers stay unscaled at ${value}%`
    );

    const source = cards.first();
    const id = Number(await source.getAttribute('data-card-id'));
    const sourceRect = await source.boundingBox();
    const boardRect = await board().boundingBox();
    const startScroll = await board().evaluate(element => element.scrollLeft);
    const scrollable = await board().evaluate(
      element => element.scrollWidth > element.clientWidth
    );

    await page.mouse.move(sourceRect.x + 40, sourceRect.y + 25);
    await page.mouse.down();
    await page.mouse.move(sourceRect.x + 70, sourceRect.y + 35, { steps: 8 });
    await page.locator('body > .crm-kanban-drag-preview').waitFor();
    await page.mouse.move(
      boardRect.x + boardRect.width - 8,
      sourceRect.y + 45,
      { steps: 25 }
    );
    if (scrollable) {
      await page.waitForFunction(
        () => {
          const element = document.querySelector('[data-kanban-board]');
          const destination = element
            .querySelector('[data-stage-id]:last-child')
            .getBoundingClientRect();
          const viewport = element.getBoundingClientRect();
          // A drag succeeds when the destination is reachable; it need not scroll
          // to the terminal padding after the last column.
          return (
            element.scrollLeft > 0 &&
            destination.x + destination.width / 2 < viewport.right - 30
          );
        },
        null,
        { timeout: 12000 }
      );
      const endScroll = await board().evaluate(element => element.scrollLeft);
      assert(
        endScroll > startScroll,
        'Dragging at the right edge must auto-scroll the board'
      );
    }
    const destination = fixture.stage_ids.at(-1);
    const target = await stage(destination)
      .locator(':scope > div')
      .boundingBox();
    const responsePromise = page.waitForResponse(
      response =>
        response.url().endsWith(`/crm/cards/${id}/move`) &&
        response.request().method() === 'POST'
    );
    await page.mouse.move(target.x + 55, target.y + 65, { steps: 12 });
    await page.waitForTimeout(200);
    await page.mouse.up();
    const response = await responsePromise;
    assert.equal(response.status(), 200);
    assert.equal(Number((await response.json()).payload.stage_id), destination);
    await visit();
    await stage(destination).locator(`[data-card-id="${id}"]`).waitFor();
    record(
      `Mouse drag to last stage${scrollable ? ' with edge auto-scroll' : ''} and server persistence at ${value}%`
    );
  }

  await zoom(87);
  const search = page.getByPlaceholder('Buscar por nome');
  await search.fill('Resultado inexistente QA839');
  await search.press('Enter');
  await page.waitForFunction(() => !document.querySelector('[data-card-id]'));
  assert.equal(await trigger().innerText(), '87%');
  await search.fill('');
  await search.press('Enter');
  await page.locator('[data-card-id]').first().waitFor();
  assert.equal(await trigger().innerText(), '87%');
  record('Search updates and restores cards without resetting zoom');

  await context.close();
  context = await chromium.launchPersistentContext(
    `${directory}/browser-profile`,
    {
      headless: true,
      viewport: { width: 1600, height: 1000 },
      locale: 'pt-BR',
    }
  );
  page = await context.newPage();
  watchErrors();
  await visit();
  assert.equal(await trigger().innerText(), '87%');
  record(
    'Exact 87% preference survives closing and restarting the actual browser process'
  );
  assert.deepEqual(errors, []);
  record('No browser runtime errors during the additional interactions');
} catch (error) {
  checks.push({ name: 'Failure', status: 'failed', message: error.message });
  await page.screenshot({ path: `${directory}/failure.png` }).catch(() => {});
  console.error(error);
  console.error('Board', await board().boundingBox());
  console.error(
    'Stages',
    await page.locator('[data-stage-id]').evaluateAll(nodes =>
      nodes.map(node => ({
        id: node.dataset.stageId,
        bounds: node.getBoundingClientRect().toJSON(),
      }))
    )
  );
  process.exitCode = 1;
} finally {
  await writeFile(
    `${directory}/report.json`,
    JSON.stringify({ checks, errors }, null, 2)
  );
  await context.close();
}
