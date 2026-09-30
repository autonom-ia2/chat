import { test, expect } from '@playwright/test';
import { session } from './helpers';

for (const width of [390, 1024, 1630]) {
  test(`attribute central actions remain visible and usable at ${width}px`, async ({
    page,
    request,
  }) => {
    await page.setViewportSize({ width, height: 844 });
    const { fixture: f } = await session(page, request);
    await page.goto(
      `/app/accounts/${f.account_id}/settings/custom-attributes/list`
    );
    await page.getByRole('button', { name: 'Contato', exact: true }).click();
    for (const { button, title } of [
      { button: 'Configurar campos', title: 'Configurar campos' },
      { button: 'Criar atributo personalizado', title: 'Criar atributo' },
    ]) {
      const action = page.getByRole('button', { name: button, exact: true });
      await expect(action).toBeVisible();
      const box = await action.boundingBox();
      expect(box).not.toBeNull();
      expect(box!.x).toBeGreaterThanOrEqual(0);
      expect(box!.x + box!.width).toBeLessThanOrEqual(width);
      await action.click();
      const dialog = page.getByRole('dialog');
      await expect(
        dialog.getByText(title, { exact: true }).first()
      ).toBeVisible();
      await dialog
        .getByRole('button', { name: 'Cancelar', exact: true })
        .click();
      await expect(dialog).toBeHidden();
    }
  });

  test(`the relationship home keeps its reference structure at ${width}px`, async ({
    page,
    request,
  }) => {
    await page.setViewportSize({ width, height: 930 });
    const { fixture: f } = await session(page, request);
    await page.goto(`/app/accounts/${f.account_id}/relationships`);
    await expect(
      page.getByRole('heading', { name: 'Relacionamentos', exact: true })
    ).toBeVisible();
    const home = page.locator('main > main').filter({
      has: page.getByRole('heading', { name: 'Relacionamentos', exact: true }),
    });
    await expect(home).toHaveCount(1);
    const cards = home.locator('article');
    await expect(cards).toHaveCount(3);
    const labels = ['Abrir contatos', 'Abrir empresas', 'Configurar atributos'];
    for (let index = 0; index < labels.length; index += 1) {
      const link = cards
        .nth(index)
        .getByRole('link', { name: labels[index], exact: true });
      await link.scrollIntoViewIfNeeded();
      await expect(link).toBeVisible();
      const box = await link.boundingBox();
      expect(box).not.toBeNull();
      expect(box!.height).toBeGreaterThanOrEqual(44);
      expect(box!.x).toBeGreaterThanOrEqual(0);
      expect(box!.x + box!.width).toBeLessThanOrEqual(width + 1);
      expect(await cards.nth(index).locator('ul li').count()).toBe(3);
    }
    if (width === 1630) {
      const boxes = await cards.evaluateAll(nodes =>
        nodes.map(node => ({
          top: node.getBoundingClientRect().top,
          height: node.getBoundingClientRect().height,
        }))
      );
      expect(new Set(boxes.map(box => Math.round(box.top))).size).toBe(1);
      expect(
        Math.max(...boxes.map(box => box.height)) -
          Math.min(...boxes.map(box => box.height))
      ).toBeLessThan(2);
    }
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    await home.evaluate(node => {
      node.scrollTop = 0;
    });
    await page.screenshot({
      path: `../../.codex/visual-776/contract-home-${width}.png`,
    });
  });
}

test('company media popovers remain inside the real mobile sidebar interaction', async ({
  page,
  request,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const { fixture: f } = await session(page, request);
  await page.goto(`/app/accounts/${f.account_id}/companies/${f.company_id}`);
  const toggle = page.locator('[data-details-sidebar-toggle]');
  await toggle.click();
  const sidebar = page.locator('#details-sidebar-content');
  await expect(sidebar).toBeVisible();
  await sidebar.getByRole('button', { name: 'Mídias', exact: true }).click();
  await sidebar.getByRole('button', { name: 'Filtros', exact: true }).click();
  await sidebar.getByRole('button', { name: 'Contatos', exact: true }).click();
  const popup = page.locator('[data-relationships-media-popover]');
  const search = popup.getByRole('searchbox', {
    name: 'Buscar contato',
    exact: true,
  });
  await search.click();
  await search.fill('Ana');
  await expect(sidebar).toBeVisible();
  await expect(search).toBeVisible();
  await popup.getByRole('button', { name: 'Ana QA', exact: true }).click();
  await expect(sidebar).toBeVisible();
  await sidebar
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await sidebar.getByRole('button', { name: 'Filtros', exact: true }).click();
  const actions = sidebar
    .getByRole('button', { name: 'Ações', exact: true })
    .first();
  await actions.scrollIntoViewIfNeeded();
  await actions.click();
  await expect(
    popup.getByRole('button', { name: 'Baixar original', exact: true })
  ).toBeVisible();
  await expect(sidebar).toBeVisible();
  await popup
    .getByRole('button', { name: 'Baixar original', exact: true })
    .focus();
  await expect(sidebar).toBeVisible();
  await page.screenshot({
    path: '../../.codex/visual-776/contract-mobile-media-popover.png',
  });
});

test('media details keep the relationship breadcrumb, readable metadata and a real thumbnail', async ({
  page,
  request,
}) => {
  const { fixture: f } = await session(page, request);
  await page.goto(
    `/app/accounts/${f.account_id}/companies/${f.company_id}/media`
  );
  await expect(
    page.getByRole('link', { name: 'Voltar à empresa', exact: true })
  ).toBeVisible();
  await expect(
    page
      .locator('main nav')
      .getByRole('link', { name: 'Relacionamentos', exact: true })
  ).toBeVisible();
  await expect(page.locator('tbody [data-media-row]')).toHaveCount(25);
  await expect(
    page.locator('tbody').getByText('application/pdf', { exact: true })
  ).toHaveCount(0);
  const preview = page.locator('tbody img[src^="blob:"]').first();
  await expect(preview).toBeVisible({ timeout: 20000 });
  expect(
    await preview.evaluate((image: HTMLImageElement) => image.naturalWidth)
  ).toBeGreaterThan(0);
  await page.screenshot({
    path: '../../.codex/visual-776/contract-media-expanded.png',
  });
});
