import { test, expect } from '@playwright/test';
import { session, fieldsSection, openContact } from './helpers';

for (const width of [390, 1024, 1630]) {
  test(`contact fields and modal fit the ${width}px viewport`, async ({
    page,
    request,
  }) => {
    await page.setViewportSize({ width, height: 930 });
    const { fixture: f } = await session(page, request);
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await openContact(page, f.account_id, f.contact_id);
    const create = fieldsSection(page).getByRole('button', {
      name: 'Criar atributo',
      exact: true,
    });
    await expect(create).toBeVisible();
    await create.scrollIntoViewIfNeeded();
    await expect
      .poll(async () => {
        const box = await create.boundingBox();
        return Boolean(box && box.x >= 0 && box.x + box.width <= width);
      })
      .toBe(true);
    await create.click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    const name = dialog.getByRole('textbox', { name: 'Nome', exact: true });
    await name.fill('Rascunho visual não salvo');
    await expect(name).toBeFocused();
    const box = await dialog.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(width + 1);
    await page.screenshot({
      path: `../../.codex/relationships/modal-${width}.png`,
      fullPage: false,
    });
    await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await expect(dialog).not.toBeVisible();
    await expect(create).toBeFocused();
    await page.screenshot({
      path: `../../.codex/relationships/contact-${width}-settled.png`,
      fullPage: false,
    });
    expect(errors).toEqual([]);
    await expect(page.locator('vite-error-overlay')).toHaveCount(0);
  });
}

test('company media renders an actual authorized thumbnail in the narrow existing sidebar', async ({
  page,
  request,
}) => {
  const { fixture: f } = await session(page, request);
  await page.goto(`/app/accounts/${f.account_id}/companies/${f.company_id}`);
  await page.getByRole('button', { name: 'Mídias', exact: true }).click();
  const images = page.locator('img[src^="blob:"]');
  await expect(images.first()).toBeVisible({ timeout: 20000 });
  const width = await images
    .first()
    .evaluate((image: HTMLImageElement) => image.naturalWidth);
  expect(width).toBeGreaterThan(0);
  await expect(
    page.getByRole('button', { name: 'Visualizar tudo', exact: true })
  ).toBeVisible();
  await page.screenshot({
    path: '../../.codex/relationships/company-media-thumbnails-real.png',
    fullPage: false,
  });
});

test('the same fields and dialog remain usable in the existing dark theme', async ({
  page,
  request,
}) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  const { fixture: f } = await session(page, request);
  await openContact(page, f.account_id, f.contact_id);
  const create = fieldsSection(page).getByRole('button', {
    name: 'Criar atributo',
    exact: true,
  });
  await expect(create).toBeVisible();
  expect(
    await page.locator('body').evaluate(body => body.classList.contains('dark'))
  ).toBe(true);
  await create.click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog
    .getByRole('textbox', { name: 'Nome', exact: true })
    .fill('Rascunho de tema escuro');
  await dialog
    .getByRole('textbox', { name: 'Descrição', exact: true })
    .fill('Descrição sintética não salva');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeEnabled();
  await page.screenshot({
    path: '../../.codex/relationships/modal-dark-real.png',
    fullPage: false,
  });
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(create).toBeFocused();
});
