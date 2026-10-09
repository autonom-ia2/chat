import { expect, test, type Locator, type Page } from '@playwright/test';
import { expectNoSeriousA11y } from '../../helpers/expectNoSeriousA11y';
import {
  agentPath,
  agentsListPath,
  conversationPath,
  createTransportLatch,
  fixtureAgent,
  gotoAgentsList,
  loadAgentsPreviewManifest,
  previewSession,
  screenshotPath,
} from '../../fixtures/agents';

type PreviewManifest = Awaited<ReturnType<typeof loadAgentsPreviewManifest>>;
let preview!: PreviewManifest;

test.beforeAll(async () => {
  preview = await loadAgentsPreviewManifest();
});

const previewBaseURL = () => {
  const value = process.env.AGENTS_PREVIEW_URL;
  if (!value) throw new Error('AGENTS_PREVIEW_URL is required');
  return value;
};

const list = (page: Page) => page.locator('[aria-label="Agentes"]');

const expectNoHorizontalOverflow = async (page: Page) => {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
};

const expectMinTouchTarget = async (target: Locator) => {
  const box = await target.boundingBox();
  expect(box).not.toBeNull();
  expect(box?.height).toBeGreaterThanOrEqual(44);
};

test.describe('F1 Seus agentes — telas reais', () => {
  test('mostra a lista real da conta com estados e resumo da projeção', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
    });
    await gotoAgentsList(page, account.id);

    await expect(
      page.getByRole('heading', { name: 'Seus agentes' })
    ).toBeVisible();
    await expect(list(page)).toBeVisible();
    for (const key of ['clara', 'pausado', 'rascunho-e1']) {
      const agent = fixtureAgent(account, key);
      await expect(page.locator(`[data-agent-id="${agent.id}"]`)).toBeVisible();
    }
    await expect(page.locator('[data-summary-chips]')).toBeVisible();
    await expectMinTouchTarget(page.locator('[data-action="open"]').first());
    await expectMinTouchTarget(
      page.locator('[data-action="continue"]').first()
    );
    await expectMinTouchTarget(page.locator('[data-action="more"]').first());
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'lista-real'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);

    const lowerAgent = fixtureAgent(account, 'clara');
    const lowerRow = page.locator(`[data-agent-id="${lowerAgent.id}"]`);
    await lowerRow.scrollIntoViewIfNeeded();
    await expect(lowerRow).toBeVisible();
    const pauseNotice = page.locator('[data-pause-notice]');
    await pauseNotice.scrollIntoViewIfNeeded();
    await expect(pauseNotice).toBeVisible();
    const viewport = page.viewportSize();
    if (viewport && viewport.width < 768) {
      const noticeBox = await pauseNotice.boundingBox();
      const launcher = page.locator('#mobile-sidebar-launcher');
      await expect(launcher).toBeVisible();
      const launcherBox = await launcher.boundingBox();
      if (!noticeBox || !launcherBox) {
        throw new Error('mobile_pause_notice_geometry_missing');
      }
      expect(noticeBox.y + noticeBox.height).toBeLessThanOrEqual(launcherBox.y);
    }
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'lista-real-lower'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
  });

  test('mostra o vazio real quando a conta não tem agentes', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.empty;
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
    });
    await gotoAgentsList(page, account.id);

    await expect(page.locator('[data-empty-hero]')).toBeVisible();
    await expect(page.locator('[data-empty-hero] h1')).toHaveCount(1);
    const create = page.getByRole('button', {
      name: 'Criar meu primeiro agente',
      exact: true,
    });
    await expect(create).toBeVisible();
    await expectMinTouchTarget(create);
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'vazio-real'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
  });

  test('preserva menu, foco e confirmações sem escrever antes de confirmar', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
    });
    await gotoAgentsList(page, account.id);

    const draft = fixtureAgent(account, 'rascunho-e1');
    const draftRow = page.locator(`[data-agent-id="${draft.id}"]`);
    const draftMenu = draftRow.locator('[data-action="more"]');
    await draftMenu.click();
    await expect(draftRow.locator('[role="menu"]')).toBeVisible();
    await expect(draftMenu).toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(draftRow.locator('[role="menu"]')).toHaveCount(0);
    await expect(draftMenu).toBeFocused();

    await draftMenu.click();
    await draftRow.locator('[data-action="delete"]').click();
    await expect(draftRow.locator('[role="menu"]')).toHaveCount(0);
    const deleteDialog = page.locator('dialog[open]');
    await expect(deleteDialog).toBeVisible();
    await expect(deleteDialog).toContainText('O rascunho sai da lista.');
    await page.screenshot({
      path: await screenshotPath(
        testInfo.project.name,
        'dialog-excluir-cancelar'
      ),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
    await deleteDialog
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    await expect(deleteDialog).toHaveCount(0);
    await expect(draftMenu).toBeFocused();

    const internal = fixtureAgent(account, 'interno');
    const internalRow = page.locator(`[data-agent-id="${internal.id}"]`);
    const internalSwitch = internalRow.getByRole('switch');
    await internalSwitch.click();
    const internalDialog = page.locator('dialog[open]');
    await expect(internalDialog).toBeVisible();
    await expect(internalDialog).toContainText(
      `O ${internal.name} some do painel das conversas até você ligar de novo.`
    );
    await page.screenshot({
      path: await screenshotPath(
        testInfo.project.name,
        'dialog-pausar-interno-cancelar'
      ),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
    await internalDialog
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    await expect(internalDialog).toHaveCount(0);
    await expect(internalSwitch).toBeFocused();
    await expect(internalRow).toHaveAttribute('data-state', 'E5');
    await expectNoHorizontalOverflow(page);
    await expectNoSeriousA11y(page);
  });

  test('expõe o loading real durante um atraso de transporte nomeado', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    const transport = createTransportLatch();
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
      scenario: {
        kind: 'transport_delay',
        until: transport.until,
        matches: request =>
          new URL(request.url()).pathname === agentsListPath(account.id),
      },
    });

    const navigation = page.goto(`/app/accounts/${account.id}/agents`);
    try {
      await expect(page.locator('[aria-busy="true"]')).toBeVisible();
      await page.screenshot({
        path: await screenshotPath(testInfo.project.name, 'loading-busy-real'),
        fullPage: false,
      });
    } finally {
      transport.release();
    }
    await navigation;
    await expect(
      page.getByRole('heading', { name: 'Seus agentes' })
    ).toBeVisible();
    await expectNoHorizontalOverflow(page);
    await expectNoSeriousA11y(page);
  });

  test('mostra o erro real quando o transporte local falha', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
      scenario: {
        kind: 'provider_error',
        matches: request =>
          new URL(request.url()).pathname === agentsListPath(account.id),
      },
    });

    await page.goto(`/app/accounts/${account.id}/agents`);
    await expect(page.getByRole('alert')).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Não deu para carregar seus agentes' })
    ).toBeVisible();
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'erro-real'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
  });

  test('mantém a lista em modo somente leitura para o viewer', async ({
    page,
    request,
  }, testInfo) => {
    const account = preview.accounts.a;
    await previewSession({
      page,
      request,
      account,
      role: 'viewer',
      baseURL: previewBaseURL(),
    });
    await gotoAgentsList(page, account.id);

    await expect(
      page.getByRole('heading', { name: 'Seus agentes' })
    ).toBeVisible();
    await expect(page.locator('[data-create-agent]')).toHaveCount(0);
    await expect(page.locator('[data-action="continue"]')).toHaveCount(0);
    await expect(page.locator('[aria-haspopup="menu"]')).toHaveCount(0);
    await expect(
      page.getByText('Você pode ver e testar os agentes.', { exact: false })
    ).toBeVisible();
    const open = page.locator('[data-action="open"]').first();
    await expect(open).toBeVisible();
    await expectMinTouchTarget(open);
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'viewer-real'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
  });

  test('persiste pausa, religação e exclusão pelo contrato real', async ({
    page,
    request,
  }, testInfo) => {
    test.skip(
      testInfo.project.name !== 'chromium-1440-light',
      'Mutação de fixture roda uma vez; as telas já cobrem todos os viewports e temas.'
    );

    const account = preview.accounts.a;
    const active = fixtureAgent(account, 'clara');
    const draft = fixtureAgent(account, 'rascunho-mutacao');
    const pauseConversation = account.pauseConversation;
    expect(account.roleIds).toEqual(
      expect.objectContaining({
        admin: expect.any(Number),
        editor: expect.any(Number),
        viewer: expect.any(Number),
      })
    );
    expect(pauseConversation).toBeDefined();
    if (!pauseConversation) {
      throw new Error('F1 preview manifest is missing pauseConversation');
    }
    expect(String(pauseConversation.agentId)).toBe(String(active.id));
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: previewBaseURL(),
    });
    await gotoAgentsList(page, account.id);

    const beforeConversationResponse = await api.get(
      conversationPath(account.id, pauseConversation.displayId)
    );
    expect(beforeConversationResponse.ok()).toBeTruthy();
    const beforeConversation = await beforeConversationResponse.json();
    expect(beforeConversation.status).toBe(pauseConversation.status);
    expect(beforeConversation.meta.assignee_type).toBe('AgentBot');
    expect(Number(beforeConversation.meta.assignee.id)).toBe(
      pauseConversation.agentBotId
    );

    const pauseRequestPromise = page.waitForRequest(
      requestForPatch =>
        new URL(requestForPatch.url()).pathname ===
          agentPath(account.id, active.id) &&
        requestForPatch.method() === 'PATCH'
    );
    const pauseResponsePromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentPath(account.id, active.id) &&
        response.request().method() === 'PATCH'
    );
    const pauseListPromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentsListPath(account.id) &&
        response.request().method() === 'GET'
    );

    const activeRow = page.locator(`[data-agent-id="${active.id}"]`);
    await activeRow.getByRole('switch').click();
    const pauseDialog = page.locator('dialog[open]');
    await expect(pauseDialog).toBeVisible();
    await expect(pauseDialog).toContainText(
      'As conversas novas vão direto para a equipe'
    );
    await pauseDialog
      .getByRole('button', { name: 'Pausar', exact: true })
      .click();

    const [pauseRequest, pauseResponse, pauseListResponse] = await Promise.all([
      pauseRequestPromise,
      pauseResponsePromise,
      pauseListPromise,
    ]);
    expect(pauseRequest.postDataJSON()).toEqual({
      status: 'paused',
      enabled: false,
    });
    expect(pauseResponse.ok()).toBeTruthy();
    const pausedList = await pauseListResponse.json();
    expect(
      pausedList.payload.find(
        (agent: { id: string | number }) =>
          String(agent.id) === String(active.id)
      ).state.code
    ).toBe('E6');
    await page.reload();
    await expect(
      page.locator(`[data-agent-id="${active.id}"]`)
    ).toHaveAttribute('data-state', 'E6');

    const afterPauseConversationResponse = await api.get(
      conversationPath(account.id, pauseConversation.displayId)
    );
    expect(afterPauseConversationResponse.ok()).toBeTruthy();
    const afterPauseConversation = await afterPauseConversationResponse.json();
    expect(afterPauseConversation.status).toBe('open');
    expect(afterPauseConversation.meta.assignee).toBeUndefined();
    expect(afterPauseConversation.meta.assignee_type).toBeUndefined();

    const reconnectRequestPromise = page.waitForRequest(
      requestForPatch =>
        new URL(requestForPatch.url()).pathname ===
          agentPath(account.id, active.id) &&
        requestForPatch.method() === 'PATCH'
    );
    const reconnectResponsePromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentPath(account.id, active.id) &&
        response.request().method() === 'PATCH'
    );
    const reconnectListPromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentsListPath(account.id) &&
        response.request().method() === 'GET'
    );

    await page
      .locator(`[data-agent-id="${active.id}"]`)
      .getByRole('switch')
      .click();
    await expect(page.locator('dialog[open]')).toHaveCount(0);

    const [reconnectRequest, reconnectResponse, reconnectListResponse] =
      await Promise.all([
        reconnectRequestPromise,
        reconnectResponsePromise,
        reconnectListPromise,
      ]);
    expect(reconnectRequest.postDataJSON()).toEqual({
      status: 'active',
      enabled: true,
    });
    expect(reconnectResponse.ok()).toBeTruthy();
    const activeList = await reconnectListResponse.json();
    expect(
      activeList.payload.find(
        (agent: { id: string | number }) =>
          String(agent.id) === String(active.id)
      ).state.code
    ).toBe('E5');
    await page.reload();
    await expect(
      page.locator(`[data-agent-id="${active.id}"]`)
    ).toHaveAttribute('data-state', 'E5');

    const deleteRequestPromise = page.waitForRequest(
      requestForDelete =>
        new URL(requestForDelete.url()).pathname ===
          agentPath(account.id, draft.id) &&
        requestForDelete.method() === 'DELETE'
    );
    const deleteResponsePromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentPath(account.id, draft.id) &&
        response.request().method() === 'DELETE'
    );
    const deleteListPromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentsListPath(account.id) &&
        response.request().method() === 'GET'
    );

    const draftRow = page.locator(`[data-agent-id="${draft.id}"]`);
    await draftRow.locator('[data-action="more"]').click();
    await draftRow.locator('[data-action="delete"]').click();
    const deleteDialog = page.locator('dialog[open]');
    await expect(deleteDialog).toBeVisible();
    await expect(deleteDialog).toContainText('O rascunho sai da lista.');
    await deleteDialog
      .getByRole('button', { name: 'Excluir rascunho', exact: true })
      .click();

    const [deleteRequest, deleteResponse, deleteListResponse] =
      await Promise.all([
        deleteRequestPromise,
        deleteResponsePromise,
        deleteListPromise,
      ]);
    expect(deleteRequest.postData()).toBeNull();
    expect(deleteResponse.status()).toBe(204);
    expect(deleteListResponse.ok()).toBeTruthy();
    const afterDelete = await deleteListResponse.json();
    expect(
      afterDelete.payload.some(
        (agent: { id: string | number }) =>
          String(agent.id) === String(draft.id)
      )
    ).toBe(false);
    const finalListResponsePromise = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === agentsListPath(account.id) &&
        response.request().method() === 'GET'
    );
    await page.reload();
    const finalListResponse = await finalListResponsePromise;
    expect(finalListResponse.ok()).toBeTruthy();
    const finalList = await finalListResponse.json();
    expect(
      finalList.payload.some(
        (agent: { id: string | number }) =>
          String(agent.id) === String(draft.id)
      )
    ).toBe(false);
    await expect(
      page.getByRole('heading', { name: 'Seus agentes' })
    ).toBeVisible();
    await expect(list(page)).toBeVisible();
    await expect(page.locator('[aria-busy="true"]')).toHaveCount(0);
    await expect(activeRow).toBeVisible();
    await expect(page.locator(`[data-agent-id="${draft.id}"]`)).toHaveCount(0);
    await expectNoHorizontalOverflow(page);
    await page.screenshot({
      path: await screenshotPath(testInfo.project.name, 'mutacoes-reais'),
      fullPage: false,
    });
    await expectNoSeriousA11y(page);
  });
});
