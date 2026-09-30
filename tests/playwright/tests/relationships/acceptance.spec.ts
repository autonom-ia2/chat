import { test, expect } from '@playwright/test';
import {
  session,
  configure,
  fieldsSection,
  fieldByName,
  setSwitch,
} from './helpers';

let pageErrors: string[];
let missingAuth: string[];
test.beforeEach(async ({ page }) => {
  pageErrors = [];
  missingAuth = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('request', request => {
    const url = new URL(request.url());
    if (
      url.pathname.startsWith('/api/v1/accounts/') &&
      (url.pathname.includes('/relationships/') ||
        url.pathname.includes('/media')) &&
      !request.headers()['access-token']
    )
      missingAuth.push(url.pathname);
  });
});
test.afterEach(async ({ page }) => {
  expect(pageErrors).toEqual([]);
  expect(missingAuth).toEqual([]);
  await expect(page.locator('vite-error-overlay')).toHaveCount(0);
});

test('home and existing contact links preserve accessible views without duplicate sidebar entries', async ({
  page,
  request,
}) => {
  const { fixture: f } = await session(page, request);
  await page.goto(`/app/accounts/${f.account_id}/relationships`);
  await expect(
    page.getByRole('heading', { name: 'Relacionamentos', exact: true })
  ).toBeVisible();
  for (const name of ['Contatos', 'Empresas', 'Atributos personalizados'])
    await expect(
      page.getByRole('heading', { name, exact: true })
    ).toBeVisible();
  const sidebar = page.locator('aside');
  await expect(
    sidebar.getByRole('button', { name: 'Contatos', exact: true })
  ).toHaveCount(0);
  await expect(
    sidebar.getByRole('button', { name: 'Empresas', exact: true })
  ).toHaveCount(0);
  await page.screenshot({ path: '../../.codex/relationships/home-real.png' });
  await page.goto(`/app/accounts/${f.account_id}/contacts?page=1`);
  await expect(page.getByText('Ana QA', { exact: true }).first()).toBeVisible();
  const selector = page.getByRole('combobox', {
    name: 'Visão de contatos',
    exact: true,
  });
  await selector.click();
  await expect(
    page.getByRole('option', { name: 'Ativo', exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('option', {
      name: 'Marcado com: homologacao-757',
      exact: true,
    })
  ).toBeVisible();
  await page.getByRole('option', { name: 'Ativo', exact: true }).click();
  await expect(page).toHaveURL(url =>
    url.pathname.endsWith('/contacts/active')
  );
  await page.goto(
    `/app/accounts/${f.account_id}/contacts/${f.contact_id}?page=1`
  );
  await expect(
    page.getByRole('button', { name: 'Atualizar contato', exact: true })
  ).toBeVisible();
});

test('existing values, zero, false and calendar dates survive center edits and reload', async ({
  page,
  request,
}) => {
  const { fixture: f, api } = await session(page, request);
  await configure(api, f.account_id, {
    contact_details: { mode: 'custom', ids: Object.values(f.definitions) },
  });
  await page.goto(`/app/accounts/${f.account_id}/contacts/${f.contact_id}`);
  await expect(
    fieldByName(page, 'Número de usuários').getByText('0', { exact: true })
  ).toBeVisible();
  await expect(
    fieldByName(page, 'Cliente estratégico').getByText('Não', { exact: true })
  ).toBeVisible();
  await expect(
    fieldByName(page, 'Data de início').getByText('29/09/2026', { exact: true })
  ).toBeVisible();
  const cargo = fieldByName(page, 'Cargo');
  await cargo.getByRole('button', { name: 'Editar', exact: true }).click();
  await cargo
    .getByRole('textbox', { name: 'Cargo', exact: true })
    .fill('Diretora QA');
  await cargo.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(cargo.getByRole('status')).toHaveText('Salvo');
  const date = fieldByName(page, 'Data de início');
  await date.getByRole('button', { name: 'Editar', exact: true }).click();
  await expect(date.locator('input[type="date"]')).toHaveValue('2026-09-29');
  await date.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(date.getByRole('status')).toHaveText('Salvo');
  const stored = await (
    await api.get(`/api/v1/accounts/${f.account_id}/contacts/${f.contact_id}`)
  ).json();
  const values = stored.payload?.custom_attributes || stored.custom_attributes;
  expect(values.job_title).toBe('Diretora QA');
  expect(values.numero_usuarios).toBe(0);
  expect(values.cliente_estrategico).toBe(false);
  expect(values.data_inicio).toBe('2026-09-29');
  await page.reload();
  await expect(
    fieldByName(page, 'Cargo').getByText('Diretora QA', { exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Atualizar contato', exact: true })
  ).toBeVisible();
  await page.screenshot({
    path: '../../.codex/relationships/contact-fields-real.png',
    fullPage: false,
  });
});

test('global sidebar configuration stays inside the actual accordion and an empty selection is not legacy mode', async ({
  page,
  request,
}) => {
  const { fixture: f, api } = await session(page, request);
  await configure(api, f.account_id, {
    contact_sidebar: { mode: 'custom', ids: [f.definitions.job_title] },
  });
  const inboxes = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `/api/v1/accounts/${f.account_id}/inboxes` &&
      response.request().method() === 'GET'
  );
  await page.goto(
    `/app/accounts/${f.account_id}/conversations/${f.conversation_id}`
  );
  expect((await inboxes).ok()).toBeTruthy();
  await expect(
    page.getByRole('heading', {
      name: 'Carregando caixas de entrada',
      exact: true,
    })
  ).not.toBeVisible();
  const panel = page.locator('.conversation--details').filter({
    has: page.getByRole('button', { name: 'Configurar campos', exact: true }),
  });
  await expect(
    page.getByRole('heading', { name: 'Atributos do contato', exact: true })
  ).toBeVisible();
  await expect(panel.getByText('Cargo', { exact: true })).toBeVisible();
  await expect(
    panel.getByText('Número de usuários', { exact: true })
  ).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Resolver', exact: true })
  ).toBeVisible();
  await expect(
    page.getByText('Mensagem Privada', { exact: true })
  ).toBeVisible();
  await page.screenshot({
    path: '../../.codex/relationships/conversation-accordion-real.png',
  });
  await panel
    .getByRole('button', { name: 'Configurar campos', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  await setSwitch(
    dialog.getByRole('switch', { name: 'Cargo', exact: true }),
    false
  );
  await dialog
    .getByRole('button', { name: 'Salvar configuração', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await expect(panel.getByText('Cargo', { exact: true })).toHaveCount(0);
  const current = await (
    await api.get(
      `/api/v1/accounts/${f.account_id}/relationships/configuration`
    )
  ).json();
  expect(current.configuration.surfaces.contact_sidebar).toEqual({
    mode: 'custom',
    ids: [],
  });
  await page.reload();
  await expect(
    panel.getByRole('button', { name: 'Configurar campos', exact: true })
  ).toBeVisible();
  await expect(panel.getByText('Cargo', { exact: true })).toHaveCount(0);
  await panel
    .getByRole('button', { name: 'Configurar campos', exact: true })
    .click();
  await dialog
    .getByRole('button', { name: 'Restaurar padrão', exact: true })
    .click();
  await dialog
    .getByRole('button', { name: 'Salvar configuração', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await expect(
    panel.getByRole('heading', { name: 'Cargo', exact: true })
  ).toBeVisible();
});

test('a transient focus error preserves an unsaved definition and cancellation creates nothing', async ({
  page,
  request,
}) => {
  const { fixture: f, api } = await session(page, request);
  const path = `/api/v1/accounts/${f.account_id}/relationships/configuration`;
  const before = await (await api.get(path)).json();
  await page.goto(`/app/accounts/${f.account_id}/contacts/${f.contact_id}`);
  await fieldsSection(page)
    .getByRole('button', { name: 'Criar atributo', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('Rascunho preservado QA');
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('Descrição ainda não salva');
  await page.route(`**${path}`, route =>
    route.request().method() === 'GET'
      ? route.fulfill({
          status: 503,
          json: { error: 'Synthetic transient fault' },
        })
      : route.continue()
  );
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    'Rascunho preservado QA'
  );
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await page.unroute(`**${path}`);
  const after = await (await api.get(path)).json();
  expect(after.definitions.length).toBe(before.definitions.length);
});

test('company definition creation is contextual, global and does not copy its value to contacts', async ({
  page,
  request,
}) => {
  const { fixture: f, api } = await session(page, request);
  await page.goto(`/app/accounts/${f.account_id}/companies/${f.company_id}`);
  const section = fieldsSection(page);
  await section
    .getByRole('button', { name: 'Criar atributo', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  const name = `Contrato QA ${Date.now()}`;
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await expect(
    dialog.getByRole('button', { name: 'Salvar atributo', exact: true })
  ).toBeDisabled();
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('Identificador de contrato informado pela empresa');
  await setSwitch(
    dialog.getByRole('switch', { name: 'Ficha da empresa', exact: true }),
    true
  );
  await dialog
    .getByRole('button', { name: 'Salvar atributo', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  const field = fieldByName(page, name);
  await field.getByRole('button', { name: 'Editar', exact: true }).click();
  await field
    .getByRole('textbox', { name, exact: true })
    .fill('CONTRATO-SINTETICO');
  await field.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(field.getByRole('status')).toHaveText('Salvo');
  const config = await (
    await api.get(
      `/api/v1/accounts/${f.account_id}/relationships/configuration`
    )
  ).json();
  const definition = config.definitions.find(
    (item: { attribute_display_name: string }) =>
      item.attribute_display_name === name
  );
  expect(definition.attribute_model).toBe('company_attribute');
  expect(definition.regex_pattern).toBeNull();
  const contact = await (
    await api.get(`/api/v1/accounts/${f.account_id}/contacts/${f.contact_id}`)
  ).json();
  expect(
    (contact.payload?.custom_attributes || contact.custom_attributes)[
      definition.attribute_key
    ]
  ).toBeUndefined();
  await page.reload();
  await expect(
    fieldByName(page, name).getByText('CONTRATO-SINTETICO', { exact: true })
  ).toBeVisible();
});

test('company media search spans all pages and the back link restores the media tab and query', async ({
  page,
  request,
}) => {
  const { fixture: f } = await session(page, request);
  await page.goto(`/app/accounts/${f.account_id}/companies/${f.company_id}`);
  await page.getByRole('button', { name: 'Mídias', exact: true }).click();
  await page
    .getByRole('button', { name: 'Visualizar tudo', exact: true })
    .click();
  await expect(page).toHaveURL(url => url.pathname.endsWith('/media'));
  await page
    .getByRole('searchbox', {
      name: 'Buscar por nome do arquivo',
      exact: true,
    })
    .fill('Único além');
  await page.getByRole('button', { name: 'Filtrar', exact: true }).click();
  await expect(
    page
      .locator('tbody')
      .getByText('Único além da primeira página.pdf', { exact: true })
  ).toBeVisible();
  await expect(page.locator('tbody [data-media-row]')).toHaveCount(1);
  await page.getByRole('button', { name: 'Filtros', exact: true }).click();
  await page.getByLabel('Agrupar por contato', { exact: true }).check();
  await page.getByRole('button', { name: 'Filtrar', exact: true }).click();
  await expect(page.locator('tbody [data-media-row]')).toHaveCount(1);
  await page.screenshot({
    path: '../../.codex/relationships/company-media-search-real.png',
  });
  await page
    .getByRole('link', { name: 'Voltar à empresa', exact: true })
    .click();
  await expect(
    page.getByRole('button', { name: 'Visualizar tudo', exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('searchbox', {
      name: 'Buscar por nome do arquivo',
      exact: true,
    })
  ).toHaveValue('Único além');
  await expect(
    page.getByText('Único além da primeira página.pdf', { exact: true })
  ).toBeVisible();
});

test('an ordinary agent cannot manage definitions or see another inbox media', async ({
  page,
  request,
}) => {
  const { fixture: f, api } = await session(page, request, 'agent');
  await page.goto(`/app/accounts/${f.account_id}/contacts/${f.contact_id}`);
  await expect(
    page.getByRole('button', { name: 'Atualizar contato', exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Configurar campos', exact: true })
  ).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Criar atributo', exact: true })
  ).toHaveCount(0);
  const config = await api.get(
    `/api/v1/accounts/${f.account_id}/relationships/configuration`
  );
  expect((await config.json()).can_manage).toBe(false);
  expect(
    (
      await api.patch(
        `/api/v1/accounts/${f.account_id}/relationships/configuration`,
        { configuration: { revision: 0, surfaces: {} } }
      )
    ).status()
  ).toBe(401);
  const media = await (
    await api.get(
      `/api/v1/accounts/${f.account_id}/companies/${f.company_id}/media?q=RESTRITO`
    )
  ).json();
  expect(media.meta.total).toBe(0);
  expect(media.payload).toEqual([]);
  for (const suffix of ['', '/preview']) {
    const response = await api.get(
      `/api/v1/accounts/${f.account_id}/companies/${f.company_id}/media/${f.private_attachment_id}${suffix}`
    );
    expect(response.status()).toBe(404);
  }
  const inaccessible = await api.get(
    `/api/v1/accounts/${f.second_account_id}/relationships/configuration`
  );
  expect([401, 403, 404]).toContain(inaccessible.status());
});
