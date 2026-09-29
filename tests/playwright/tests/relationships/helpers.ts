import { expect, type Page, type APIRequestContext } from '@playwright/test';
import fs from 'node:fs/promises';

export async function fixtures() {
  const filename = process.env.RELATIONSHIPS_TEST_FIXTURE;
  if (!filename) throw new Error('A synthetic local fixture file is required');
  return JSON.parse(await fs.readFile(filename, 'utf8'));
}

export async function session(
  page: Page,
  request: APIRequestContext,
  role = 'admin'
) {
  const fixture = await fixtures();
  const base = process.env.RELATIONSHIPS_TEST_URL!;
  const result = await request.post('/auth/sign_in', {
    data: {
      email: role === 'admin' ? fixture.email : fixture.agent_email,
      password: fixture.password,
    },
  });
  expect(
    result.ok(),
    'The normal authentication endpoint must accept synthetic credentials'
  ).toBeTruthy();
  const headers = result.headers();
  const auth = Object.fromEntries(
    ['access-token', 'client', 'uid', 'expiry', 'token-type'].map(key => [
      key,
      headers[key],
    ])
  );
  expect(Boolean(auth['access-token'])).toBeTruthy();
  await page.context().addCookies([
    {
      name: 'cw_d_session_info',
      value: JSON.stringify(auth),
      url: base,
      sameSite: 'Lax',
    },
  ]);
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      ['blob:', 'data:'].includes(url.protocol)
      ? route.continue()
      : route.abort();
  });
  const api = {
    get: (path: string) => request.get(path, { headers: auth }),
    patch: (path: string, data: unknown) =>
      request.patch(path, { headers: auth, data }),
    post: (path: string, data: unknown) =>
      request.post(path, { headers: auth, data }),
  };
  return { fixture, api };
}

export async function configure(
  api: Awaited<ReturnType<typeof session>>['api'],
  account: number,
  surfaces: object
) {
  const path = `/api/v1/accounts/${account}/relationships/configuration`;
  const before = await api.get(path);
  expect(before.ok()).toBeTruthy();
  const state = await before.json();
  const result = await api.patch(path, {
    configuration: { revision: state.configuration.revision, surfaces },
  });
  expect(result.ok()).toBeTruthy();
  return result.json();
}

export const fieldsSection = (page: Page) =>
  page.locator('section').filter({
    has: page.getByRole('heading', {
      name: 'Campos personalizados',
      exact: true,
    }),
  });
export const fieldByName = (page: Page, name: string) =>
  fieldsSection(page).getByRole('group', { name, exact: true });

// Wait for the actual authenticated data boundary, then assert the rendered controls.
// This avoids timing assertions against the application's initial loading screen.
export async function openContact(
  page: Page,
  account: number | string,
  contact: number | string
) {
  const configuration = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `/api/v1/accounts/${account}/relationships/configuration` &&
      response.request().method() === 'GET'
  );
  const record = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `/api/v1/accounts/${account}/contacts/${contact}` &&
      response.request().method() === 'GET'
  );
  await page.goto(`/app/accounts/${account}/contacts/${contact}`);
  expect((await record).ok()).toBeTruthy();
  expect((await configuration).ok()).toBeTruthy();
  await expect(
    page.getByRole('button', { name: 'Atualizar contato', exact: true })
  ).toBeVisible();
}
