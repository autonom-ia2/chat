import { test, expect } from '@playwright/test';

const required = (key: string) => {
  const value = process.env[key];
  if (!value)
    throw new Error(`Missing isolated synthetic fixture setting: ${key}`);
  return value;
};

test('creates through the actual modal, saves a field explicitly, and survives reload', async ({
  page,
}) => {
  const account = required('RELATIONSHIPS_TEST_ACCOUNT_ID');
  const contact = required('RELATIONSHIPS_TEST_CONTACT_ID');
  const name = `Teste relacionamento ${Date.now()}`;
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      ['blob:', 'data:'].includes(url.protocol)
      ? route.continue()
      : route.abort();
  });
  await page.goto('/app/login');
  await page
    .getByTestId('email_input')
    .fill(required('RELATIONSHIPS_TEST_EMAIL'));
  await page
    .getByTestId('password_input')
    .fill(required('RELATIONSHIPS_TEST_PASSWORD'));
  await page.getByTestId('submit_button').click();
  await page.waitForURL(url => url.pathname.startsWith('/app/accounts/'), {
    waitUntil: 'domcontentloaded',
  });
  await page.goto(`/app/accounts/${account}/contacts/${contact}`);
  await page
    .getByRole('button', { name: 'Configurar campos', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  await dialog
    .getByRole('button', { name: 'Criar atributo', exact: true })
    .click();
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('Campo sintético para aceite local da Issue 757');
  await dialog.getByLabel('Ficha do contato', { exact: true }).check();
  const definitionResponse = page.waitForResponse(
    response =>
      response.url().endsWith('/relationships/configuration') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await definitionResponse).ok()).toBeTruthy();
  await expect(dialog).not.toBeVisible();
  const fieldsSection = page.locator('section').filter({
    has: page.getByRole('heading', {
      name: 'Campos personalizados',
      exact: true,
    }),
  });
  // Anchor the field on its persistent accessible name, not on a button removed during editing.
  const field = fieldsSection.getByRole('group', { name, exact: true });
  await field.getByRole('button', { name: 'Editar', exact: true }).click();
  await field.getByRole('textbox', { name, exact: true }).fill('CEO');
  const valueResponse = page.waitForResponse(
    response =>
      response.url().includes('/relationships/contact/') &&
      response.request().method() === 'PATCH'
  );
  await fieldsSection
    .getByRole('button', { name: 'Salvar', exact: true })
    .click();
  expect((await valueResponse).ok()).toBeTruthy();
  await expect(field.getByRole('status')).toHaveText('Salvo');
  await page.reload();
  await expect(fieldsSection.getByText(name, { exact: true })).toBeVisible();
  await expect(page.getByText('CEO', { exact: true }).first()).toBeVisible();
  await page.screenshot({
    path: '../../.codex/relationships/contact-desktop.png',
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: '../../.codex/relationships/contact-mobile.png',
    fullPage: true,
  });
});
