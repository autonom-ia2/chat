import { expect, test, type Page } from '@playwright/test';
import { expectNoSeriousA11y } from '../../helpers/expectNoSeriousA11y';
import {
  agentPath,
  type PreviewApi,
  loadAgentsPreviewManifest,
  previewSession,
  screenshotPath,
} from '../../fixtures/agents';

type Manifest = Awaited<ReturnType<typeof loadAgentsPreviewManifest>>;
let preview: Manifest;
let createdAgents: Array<{ api: PreviewApi; accountId: number; id: number }> =
  [];
test.beforeEach(() => {
  createdAgents = [];
});
test.afterEach(async () => {
  for (const { api, accountId, id } of createdAgents) {
    const response = await api.delete(agentPath(accountId, id));
    expect([200, 204, 404]).toContain(response.status());
  }
});
test.beforeAll(async () => {
  preview = await loadAgentsPreviewManifest();
});

const baseURL = () => {
  const url = process.env.AGENTS_PREVIEW_URL;
  if (!url) throw new Error('local preview URL required');
  return url;
};
const screen = (page: Page, step: string) =>
  page.getByTestId(`agent-creation-${step}`);
const action = (page: Page, name: string) =>
  page.locator(`[data-action="${name}"]`);

async function capture(page: Page, project: string, name: string) {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: await screenshotPath(project, name),
    fullPage: true,
    animations: 'disabled',
  });
  await expectNoSeriousA11y(page);
}

async function createAndTest(
  page: Page,
  api: PreviewApi,
  accountId: number,
  model: string
) {
  await page.goto(`/app/accounts/${accountId}/agents/new`);
  await page.locator(`[data-model-id="${model}"]`).click();
  const opening = page.waitForResponse(
    value =>
      value.request().method() === 'POST' &&
      new URL(value.url()).pathname.endsWith('/autonomia/build_threads')
  );
  await action(page, 'creation-continue').click();
  const response = await opening;
  expect(response.status()).toBe(202);
  const thread = (await response.json()).payload;
  createdAgents.push({ api, accountId, id: thread.agent_id });
  await expect(screen(page, 'tell')).toBeVisible();
  const answers = [
    'Ajuda com perguntas de exemplo.',
    'Equipe de exemplo.',
    'Nao inventar respostas.',
    'Apoio de exemplo',
  ];
  const keys = ['negocio', 'publico', 'quando_chama', 'nome'];
  for (let index = 0; index < answers.length; index += 1) {
    await expect(
      screen(page, 'tell').locator('textarea').first()
    ).toBeEnabled();
    await screen(page, 'tell').locator('textarea').first().fill(answers[index]);
    await screen(page, 'tell')
      .getByRole('button', { name: 'Enviar', exact: true })
      .click();
    await expect
      .poll(async () => {
        const result = await api.get(
          `/api/v1/accounts/${accountId}/autonomia/build_threads/${thread.id}`
        );
        return (await result.json()).payload.state.knows[keys[index]];
      })
      .toBe(answers[index]);
    await expect(
      screen(page, 'tell')
        .getByRole('list')
        .first()
        .getByText(answers[index], { exact: true })
    ).toBeVisible();
  }
  await page.getByTestId('creation-tell-next').click();
  await expect(screen(page, 'test')).toBeVisible();
  await page.getByTestId('test-message').fill('Como voce pode ajudar?');
  await action(page, 'test-send').click();
  await expect
    .poll(
      async () =>
        (await (await api.get(agentPath(accountId, thread.agent_id))).json())
          .state.code
    )
    .toBe('E4');
  await expect(screen(page, 'test').getByRole('status')).toHaveCount(0);
  await expect(page.getByTestId('creation-test-next')).toBeEnabled();
  await page.getByTestId('creation-test-next').click();
  await expect(screen(page, 'live')).toBeVisible();
  return thread.agent_id;
}

test.describe('F2+F3 criacao completa pela aplicacao real', () => {
  test('portal abre um cenario ficticio na tela real', async ({ page }) => {
    await page.goto('/preview-criacao');
    const loginResponse = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname === '/auth/sign_in'
    );
    await page.locator('button[data-account="a"][data-target="new"]').click();
    expect((await loginResponse).status()).toBe(200);
    await expect(screen(page, 'choice')).toBeVisible();
    await expect(page.locator('[data-model-id="internal"]')).toBeVisible();
  });
  test('escolhe, responde, sai, retoma, testa, edita, testa de novo e liga', async ({
    page,
    request,
  }, testInfo) => {
    test.setTimeout(150_000);
    const account = preview.accounts.a;
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    let starts = 0;
    page.on('request', value => {
      if (
        value.method() === 'POST' &&
        new URL(value.url()).pathname.endsWith('/autonomia/build_threads')
      )
        starts += 1;
    });
    await page.goto(`/app/accounts/${account.id}/agents/new`);
    await expect(screen(page, 'choice')).toBeVisible();
    await capture(page, testInfo.project.name, 'criacao-01-escolha');
    if (testInfo.project.name.includes('400')) {
      await page.locator('[data-model-id="custom"]').scrollIntoViewIfNeeded();
      await capture(
        page,
        testInfo.project.name,
        'criacao-01b-escolha-outros-modelos'
      );
    }
    await page.locator('[data-model-id="support"]').click();
    const opening = page.waitForResponse(
      value =>
        value.request().method() === 'POST' &&
        new URL(value.url()).pathname.endsWith('/autonomia/build_threads')
    );
    await action(page, 'creation-continue').click();
    const started = await opening;
    expect(started.status()).toBe(202);
    const thread = (await started.json()).payload;
    expect(thread.agent_id).toBeGreaterThan(0);
    const agentId = thread.agent_id;
    createdAgents.push({ api, accountId: account.id, id: agentId });
    await expect(screen(page, 'tell')).toBeVisible();

    const answers = [
      'Uma loja de produtos de exemplo.',
      'Pessoas que pedem informacoes sobre os produtos.',
      'Quando nao tiver informacao suficiente.',
      'Bia',
    ];
    const keys = ['negocio', 'publico', 'quando_chama', 'nome'];
    for (let index = 0; index < answers.length; index += 1) {
      await expect(
        screen(page, 'tell').locator('textarea').first()
      ).toBeEnabled();
      await screen(page, 'tell')
        .locator('textarea')
        .first()
        .fill(answers[index]);
      if (index === 0) {
        await page.route(
          `**/autonomia/build_threads/${thread.id}/messages`,
          route => route.abort('failed'),
          { times: 1 }
        );
      }
      await screen(page, 'tell')
        .getByRole('button', { name: 'Enviar', exact: true })
        .click();
      if (index === 0) {
        await expect(screen(page, 'tell').getByRole('alert')).toContainText(
          'Não foi possível continuar a conversa.'
        );
        await screen(page, 'tell')
          .getByRole('button', { name: 'Tentar de novo', exact: true })
          .click();
      }
      await expect
        .poll(async () => {
          const result = await api.get(
            `/api/v1/accounts/${account.id}/autonomia/build_threads/${thread.id}`
          );
          return (await result.json()).payload.state.knows[keys[index]];
        })
        .toBe(answers[index]);
      await expect(
        screen(page, 'tell')
          .getByRole('list')
          .first()
          .getByText(answers[index], { exact: true })
      ).toBeVisible();
      await expect(page.getByRole('alert')).toHaveCount(0);
      await expect(
        screen(page, 'tell')
          .getByRole('log')
          .getByText(answers[index], { exact: true })
      ).toHaveCount(1);
      if (index === 1) {
        await capture(page, testInfo.project.name, 'criacao-02-conte-retomada');
        await action(page, 'creation-save-exit').click();
        await expect(
          page.getByRole('heading', { name: 'Seus agentes' })
        ).toBeVisible();
        await page
          .locator(`[data-agent-id="${agentId}"] [data-action="continue"]`)
          .click();
        await expect(screen(page, 'tell')).toBeVisible();
        const resumed = await api.get(
          `/api/v1/accounts/${account.id}/autonomia/agents/${agentId}/build_thread`
        );
        expect((await resumed.json()).payload.id).toBe(thread.id);
        expect(starts).toBe(1);
      }
    }
    await expect(page.getByTestId('creation-tell-next')).toBeEnabled();
    await capture(page, testInfo.project.name, 'criacao-03-conte-concluido');
    if (testInfo.project.name.includes('400')) {
      await screen(page, 'tell')
        .getByRole('list')
        .first()
        .scrollIntoViewIfNeeded();
      await capture(
        page,
        testInfo.project.name,
        'criacao-03b-conte-respostas-materiais'
      );
    }
    await page.getByTestId('creation-tell-next').scrollIntoViewIfNeeded();
    await capture(page, testInfo.project.name, 'criacao-03c-conte-continuar');
    await page.getByTestId('creation-tell-next').click();
    await expect(screen(page, 'test')).toBeVisible();
    const composer = page.getByTestId('test-composer');
    const messageBox = await page.getByTestId('test-message').boundingBox();
    const imageButtonBox = await composer
      .getByRole('button', { name: 'Adicionar imagem', exact: true })
      .boundingBox();
    const sendButtonBox = await action(page, 'test-send').boundingBox();
    if (!messageBox || !imageButtonBox || !sendButtonBox)
      throw new Error('Test composer controls must be visible');
    const centerY = messageBox.y + messageBox.height / 2;
    expect(
      Math.abs(imageButtonBox.y + imageButtonBox.height / 2 - centerY)
    ).toBeLessThan(1);
    expect(
      Math.abs(sendButtonBox.y + sendButtonBox.height / 2 - centerY)
    ).toBeLessThan(1);
    expect(imageButtonBox.width).toBeGreaterThanOrEqual(44);
    expect(imageButtonBox.height).toBeGreaterThanOrEqual(44);
    expect(sendButtonBox.width).toBeGreaterThanOrEqual(44);
    expect(sendButtonBox.height).toBeGreaterThanOrEqual(44);
    await composer.scrollIntoViewIfNeeded();
    await composer.screenshot({
      path: await screenshotPath(
        testInfo.project.name,
        'ajuste-composer-teste'
      ),
      animations: 'disabled',
    });
    const state = async () =>
      (await (await api.get(agentPath(account.id, agentId))).json()).state.code;
    await page.getByTestId('test-message').fill('Como voce pode ajudar?');
    await action(page, 'test-send').click();
    await expect.poll(state).toBe('E4');
    await expect(screen(page, 'test').getByRole('status')).toHaveCount(0);
    await expect(page.getByTestId('creation-test-next')).toBeEnabled();
    await capture(page, testInfo.project.name, 'criacao-04-teste-valido');
    await page.getByLabel('Nome', { exact: true }).fill('Bia revisada');
    await action(page, 'presentation-save').click();
    await expect.poll(state).toBe('E3');
    await expect(page.getByTestId('creation-test-next')).toBeDisabled();
    await capture(page, testInfo.project.name, 'criacao-05-teste-invalidado');
    await page
      .getByTestId('test-message')
      .fill('Pode me explicar o proximo passo?');
    await action(page, 'test-send').click();
    await expect.poll(state).toBe('E4');
    await page.getByTestId('creation-test-next').click();
    await expect(screen(page, 'live')).toBeVisible();
    const available = page.locator('[data-channel-id]:not([disabled])');
    const firstChannel = available.nth(0);
    const secondChannel = available.nth(1);
    const firstInboxId = Number(
      await firstChannel.getAttribute('data-channel-id')
    );
    const secondInboxId = Number(
      await secondChannel.getAttribute('data-channel-id')
    );
    await firstChannel.click();
    await secondChannel.focus();
    await secondChannel.press('Space');
    await expect(firstChannel).toHaveAttribute('aria-checked', 'true');
    await expect(secondChannel).toHaveAttribute('aria-checked', 'true');
    await firstChannel.press('Space');
    await expect(firstChannel).toHaveAttribute('aria-checked', 'false');
    await expect(secondChannel).toHaveAttribute('aria-checked', 'true');
    await firstChannel.press('Space');
    const selectedInboxIds = [firstInboxId, secondInboxId].sort(
      (a, b) => a - b
    );

    await capture(page, testInfo.project.name, 'criacao-06-ligue');

    await expect(firstChannel).toHaveAttribute('aria-checked', 'true');
    await expect(secondChannel).toHaveAttribute('aria-checked', 'true');
    await expect(action(page, 'creation-publish')).toBeEnabled();

    let refused = false;
    const publishURL = `${agentPath(account.id, agentId)}/publish`;
    await page.route(`**${publishURL}`, async route => {
      if (!refused) {
        refused = true;
        await route.abort('failed');
        return;
      }
      await route.continue();
    });
    await action(page, 'creation-publish').click();
    await expect(page.getByRole('alert')).toBeVisible();
    expect(await state()).toBe('E4');
    await expect(page.getByRole('alert')).toContainText(
      'Não foi possível ligar este agente'
    );
    await expect(
      page.getByText('AxiosError: Network Error', { exact: true })
    ).toHaveCount(0);
    await page.getByRole('alert').scrollIntoViewIfNeeded();
    await capture(
      page,
      testInfo.project.name,
      'criacao-07-falha-transporte-na-publicacao'
    );
    await action(page, 'creation-publish').click();
    await expect(screen(page, 'ready')).toBeVisible();
    expect(await state()).toBe('E5');
    const channels = await api.get(
      `${agentPath(account.id, agentId)}/channels`
    );
    const linkedChannels = (await channels.json()).payload;
    expect(
      linkedChannels.map(channel => channel.inbox_id).sort((a, b) => a - b)
    ).toEqual(selectedInboxIds);
    await expect(screen(page, 'ready').getByRole('heading')).toContainText(
      '2 caixas de entrada'
    );
    for (const channel of linkedChannels) {
      await expect(
        screen(page, 'ready').getByText(channel.inbox_name, { exact: true })
      ).toBeVisible();
    }
    await page.reload();
    await expect(screen(page, 'ready')).toBeVisible();
    for (const channel of linkedChannels) {
      await expect(
        screen(page, 'ready').getByText(channel.inbox_name, { exact: true })
      ).toBeVisible();
    }
    await expect(page.getByRole('alert')).toHaveCount(0);
    expect(starts).toBe(1);
    await capture(page, testInfo.project.name, 'criacao-08-pronto');
  });

  test('falha de transporte na abertura conserva a escolha e permite tentar novamente', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    await page.route('**/autonomia/build_threads', route =>
      route.abort('failed')
    );
    await page.goto(`/app/accounts/${account.id}/agents/new`);
    await page.locator('[data-model-id="support"]').click();
    await action(page, 'creation-continue').click();
    await expect(page.getByRole('alert')).toBeVisible();
    await expect(action(page, 'creation-continue')).toBeEnabled();
    await page.getByRole('alert').scrollIntoViewIfNeeded();
    await capture(
      page,
      testInfo.project.name,
      'criacao-09-falha-transporte-na-abertura'
    );
  });

  test('sem canal conectado preserva E4 ao deixar para depois', async ({
    page,
    request,
  }, testInfo) => {
    test.setTimeout(100_000);
    const account = preview.accounts.empty;
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    const agentId = await createAndTest(page, api, account.id, 'support');
    await expect(action(page, 'creation-publish')).toBeDisabled();
    await expect(page.locator('[data-channel-id]')).toHaveCount(0);
    await expect(page.locator('select')).toHaveCount(0);
    await capture(page, testInfo.project.name, 'criacao-10-sem-canal');
    await action(page, 'creation-stay-off').click();
    await expect(
      page.getByRole('heading', { name: 'Seus agentes' })
    ).toBeVisible();
    const agent = await api.get(agentPath(account.id, agentId));
    expect((await agent.json()).state.code).toBe('E4');
  });

  test('ajudante fica disponivel para equipe sem associar canal', async ({
    page,
    request,
  }, testInfo) => {
    test.setTimeout(100_000);
    const account = preview.accounts.a;
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    const agentId = await createAndTest(page, api, account.id, 'internal');
    await expect(page.locator('[data-channel-id]')).toHaveCount(0);
    await capture(page, testInfo.project.name, 'criacao-11-ajudante-ligue');
    await action(page, 'creation-publish').click();
    await expect(screen(page, 'ready')).toBeVisible();
    const agent = await (await api.get(agentPath(account.id, agentId))).json();
    expect(agent.actuation).toBe('internal');
    expect(agent.state.code).toBe('E5');
    expect(
      (
        await (
          await api.get(`${agentPath(account.id, agentId)}/channels`)
        ).json()
      ).payload
    ).toHaveLength(0);
    await capture(page, testInfo.project.name, 'criacao-12-ajudante-pronto');
  });
});
