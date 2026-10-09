import {
  expect,
  test,
  type APIResponse,
  type Page,
  type Request,
  type TestInfo,
} from '@playwright/test';
import { expectNoSeriousA11y } from '../../helpers/expectNoSeriousA11y';
import {
  agentPath,
  fixtureAgent,
  gestaoPreviewSession,
  loadAgentsPreviewManifest,
  loadGestaoPreviewManifest,
  panelAgentPath,
  previewSession,
  recordScreenshot,
  screenshotPath,
  type GestaoPreviewAccount,
  type PreviewAccount,
} from '../../fixtures/agents';

type CreationManifest = Awaited<
  ReturnType<typeof loadAgentsPreviewManifest>
>;
type GestaoManifest = Awaited<ReturnType<typeof loadGestaoPreviewManifest>>;
type JSONRecord = Record<string, unknown>;

let creationPreview!: CreationManifest;
let gestaoPreview!: GestaoManifest;
const restorations: Array<() => Promise<void>> = [];
const suite = process.env.AGENTS_PREVIEW_SUITE || 'creation';

test.beforeAll(async () => {
  if (suite === 'creation') {
    creationPreview = await loadAgentsPreviewManifest();
    return;
  }
  if (suite === 'gestao') {
    gestaoPreview = await loadGestaoPreviewManifest();
    return;
  }
  throw new Error('AGENTS_PREVIEW_SUITE must be creation or gestao');
});

test.beforeEach(({ page }, testInfo) => {
  page.on('pageerror', error => {
    console.error(
      `[${testInfo.project.name}] global-correcoes pageerror: ${
        error.stack || error.message
      }`
    );
  });
});

test.afterEach(async () => {
  while (restorations.length) {
    await restorations.pop()?.();
  }
});

const baseURL = () => {
  const value = process.env.AGENTS_PREVIEW_URL;
  if (!value) throw new Error('AGENTS_PREVIEW_URL is required');
  return value;
};

const creationPath = (
  accountId: number,
  agentId: string | number,
  step: 'test' | 'tell' | 'live'
) => `/app/accounts/${accountId}/agents/${agentId}/build/${step}`;

const panelPath = (
  accountId: number,
  agentId: string | number,
  tab: 'knowledge' | 'channels' | 'tune'
) => `/app/accounts/${accountId}/agents/${agentId}/${tab}`;

const buildThreadResumePath = (accountId: number, agentId: string | number) =>
  `${agentPath(accountId, agentId)}/build_thread`;

const channelsPath = (accountId: number, agentId: string | number) =>
  `${agentPath(accountId, agentId)}/channels`;

const playgroundTestPath = (accountId: number, agentId: string | number) =>
  `${agentPath(accountId, agentId)}/test`;

const expectNoHorizontalOverflow = async (page: Page) => {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
};

const capture = async (
  page: Page,
  testInfo: TestInfo,
  scenario: string,
  scrollSelector?: string
) => {
  if (scrollSelector) {
    await page.locator(scrollSelector).scrollIntoViewIfNeeded();
  }
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousA11y(page);
  const file = await screenshotPath(
    testInfo.project.name,
    `global-${scenario}`
  );
  await page.screenshot({
    path: file,
    fullPage: false,
    animations: 'disabled',
  });
  await recordScreenshot({
    scenario: `global-${scenario}`,
    project: testInfo.project.name,
    file,
  });
};

const readJSON = async (response: APIResponse) => {
  expect(response.ok()).toBe(true);
  return (await response.json()) as JSONRecord;
};

const creationAgent = (account: PreviewAccount, key: string) =>
  fixtureAgent(account, key);

const gestaoAgent = (account: GestaoPreviewAccount, key: string) => {
  const value = account.agents[key];
  if (!value) throw new Error(`GESTAO fixture agent is missing: ${key}`);
  return value;
};

const requestPath = (request: Request) => new URL(request.url()).pathname;

const assertActiveTabIsInsideTablist = async (page: Page, key: string) => {
  const geometry = await page.evaluate(tabKey => {
    const tablist = document.querySelector('[role="tablist"]');
    const tab = document.querySelector(`#agent-panel-tab-${tabKey}`);
    if (!tablist || !tab) return null;
    const listRect = tablist.getBoundingClientRect();
    const tabRect = tab.getBoundingClientRect();
    return {
      listLeft: listRect.left,
      listRight: listRect.right,
      tabLeft: tabRect.left,
      tabRight: tabRect.right,
    };
  }, key);

  expect(geometry).not.toBeNull();
  expect(geometry?.tabLeft).toBeGreaterThanOrEqual(
    (geometry?.listLeft || 0) - 1
  );
  expect(geometry?.tabRight).toBeLessThanOrEqual(
    (geometry?.listRight || 0) + 1
  );
};

test.describe('Correções globais G01–G05 — jornadas reais', () => {
  test('G01 reinicia a apresentação antes do novo teste', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'creation', 'G01 requer o manifesto F1 de criação');
    test.setTimeout(180_000);
    const account = creationPreview.accounts.b;
    if (!account) {
      throw new Error('F1 fixture account.b is required for the isolated G01 scenario');
    }
    const currentAgent = creationAgent(account, 'one-channel-e4');
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    const originalAgent = await readJSON(
      await api.get(agentPath(account.id, currentAgent.id))
    );
    const originalConfig = (originalAgent.config || {}) as JSONRecord;
    const originalName = String(originalAgent.name || currentAgent.name);
    const originalGreeting = String(
      originalAgent.greeting || originalConfig.greeting || ''
    );
    restorations.push(async () => {
      const response = await api.patch(agentPath(account.id, currentAgent.id), {
        agent: { name: originalName, greeting: originalGreeting },
      });
      expect([200, 204]).toContain(response.status());
    });
    const testPayloads: JSONRecord[] = [];

    page.on('request', currentRequest => {
      if (
        currentRequest.method() === 'POST' &&
        requestPath(currentRequest) ===
          playgroundTestPath(account.id, currentAgent.id)
      ) {
        const payload = currentRequest.postDataJSON();
        if (payload && typeof payload === 'object') {
          testPayloads.push(payload as JSONRecord);
        }
      }
    });

    await page.goto(creationPath(account.id, currentAgent.id, 'test'));
    await expect(page.getByTestId('agent-creation-test')).toBeVisible();

    const firstQuestion = 'Primeira pergunta da conversa de teste';
    await page.getByTestId('test-message').fill(firstQuestion);
    await page.getByTestId('test-send').click();
    await expect(
      page.getByRole('log').getByText(firstQuestion, { exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole('log').getByText('Olá! Posso ajudar', { exact: false })
    ).toBeVisible();
    await expect(page.getByRole('status')).toHaveCount(0);
    await expect(page.getByTestId('test-send')).toBeEnabled();
    await expect(page.getByTestId('creation-test-next')).toBeEnabled();
    await expect.poll(() => testPayloads.length).toBe(1);
    await capture(page, testInfo, 'g01-resposta-concluida');

    const newName = `${currentAgent.name} atualizado`;
    const newGreeting = 'Olá, sou o agente atualizado.';
    await page.getByTestId('presentation-name').fill(newName);
    await page.getByTestId('presentation-greeting').fill(newGreeting);
    const presentationPatch = page.waitForResponse(response =>
      response.request().method() === 'PATCH' &&
      new URL(response.url()).pathname === agentPath(account.id, currentAgent.id)
    );
    await page.locator('[data-action="presentation-save"]').click();
    expect((await presentationPatch).ok()).toBe(true);

    await expect(page.getByTestId('test-presentation-reset')).toBeVisible();
    await expect(
      page.getByTestId('test-presentation-reset')
    ).toContainText('Comece uma nova conversa');
    await expect(
      page.getByRole('log').getByText(firstQuestion, { exact: true })
    ).toHaveCount(0);
    await expect(page.getByTestId('creation-test-next')).toBeDisabled();

    const persistedAgent = await readJSON(
      await api.get(agentPath(account.id, currentAgent.id))
    );
    const persistedConfig = (persistedAgent.config || {}) as JSONRecord;
    expect(persistedAgent.greeting || persistedConfig.greeting).toBe(
      newGreeting
    );
    await capture(page, testInfo, 'g01-apresentacao-nova-conversa');

    const thirdQuestion = 'Pergunta depois da nova apresentação';
    const newTestRequest = page.waitForRequest(currentRequest =>
      currentRequest.method() === 'POST' &&
      requestPath(currentRequest) ===
        playgroundTestPath(account.id, currentAgent.id)
    );
    await page.getByTestId('test-message').fill(thirdQuestion);
    await page.getByTestId('test-send').click();
    const requestBody = (await newTestRequest).postDataJSON() as JSONRecord;
    expect(requestBody).toMatchObject({
      message: thirdQuestion,
      history: [],
    });
    await expect(
      page.getByRole('log').getByText(thirdQuestion, { exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole('log').getByText('Olá! Posso ajudar', { exact: false })
    ).toBeVisible();
    await expect(page.getByRole('status')).toHaveCount(0);
    await expect(page.getByTestId('test-send')).toBeEnabled();
    await expect(page.getByTestId('creation-test-next')).toBeEnabled();
    await expect.poll(() => testPayloads.length).toBe(2);
    await capture(page, testInfo, 'g01-novo-history-greeting');
  });

  test('G02 abre Teste E3 e Ligue E4 sem chamar resume ou criar BuildThread', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'creation', 'G02 requer o manifesto F1 de criação');
    const account = creationPreview.accounts.a;
    const e3 = creationAgent(account, 'rascunho-e3-person');
    const e4 = creationAgent(account, 'pronto-para-ligar');
    const { api } = await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    const e3Payload = await readJSON(
      await api.get(agentPath(account.id, e3.id))
    );
    const e4Payload = await readJSON(
      await api.get(agentPath(account.id, e4.id))
    );
    expect((e3Payload.state as JSONRecord).code).toBe('E3');
    expect((e4Payload.state as JSONRecord).code).toBe('E4');
    const forbiddenBuildRequests: string[] = [];
    page.on('request', currentRequest => {
      const path = requestPath(currentRequest);
      if (
        path.endsWith('/build_thread') ||
        path.endsWith('/autonomia/build_threads') ||
        path.includes('/autonomia/build_threads/')
      ) {
        forbiddenBuildRequests.push(`${currentRequest.method()} ${path}`);
      }
    });

    await page.goto(creationPath(account.id, e3.id, 'test'));
    await expect(page.getByTestId('agent-creation-test')).toBeVisible();
    await capture(page, testInfo, 'g02-deep-test-e3');

    await page.goto(creationPath(account.id, e4.id, 'live'));
    await expect(page.getByTestId('agent-creation-live')).toBeVisible();
    await expect(
      page
        .getByTestId('agent-creation-live')
        .locator('[data-channel-id]')
        .first()
    ).toBeVisible();
    await capture(page, testInfo, 'g02-deep-ligue-e4');

    expect(forbiddenBuildRequests).toEqual([]);
  });

  test('G02 mantém Conte no contexto e permite retry de uma falha nomeada de resume', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'creation', 'G02 requer o manifesto F1 de criação');
    const account = creationPreview.accounts.a;
    const draft = creationAgent(account, 'rascunho-e1');
    const resumePath = buildThreadResumePath(account.id, draft.id);
    let resumeRequests = 0;
    let startRequests = 0;

    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    page.on('request', currentRequest => {
      const path = requestPath(currentRequest);
      if (path === resumePath) resumeRequests += 1;
      if (
        currentRequest.method() === 'POST' &&
        path.endsWith('/autonomia/build_threads')
      ) {
        startRequests += 1;
      }
    });

    await test.step('fault:conte-resume-first-attempt', async () => {
      await page.route(
        `**${resumePath}`,
        route => route.abort('failed'),
        { times: 1 }
      );
    });
    await page.goto(creationPath(account.id, draft.id, 'tell'));
    await expect(page.getByTestId('creation-entry-error')).toBeVisible();
    await expect(
      page.locator('[data-action="creation-entry-retry"]')
    ).toBeVisible();
    await capture(page, testInfo, 'g02-conte-resume-erro');

    await page.locator('[data-action="creation-entry-retry"]').click();
    await expect(page.getByTestId('agent-creation-tell')).toBeVisible();
    await expect.poll(() => resumeRequests).toBe(2);
    expect(startRequests).toBe(0);
    await capture(page, testInfo, 'g02-conte-resume-recuperado');
  });

  test('G02 mantém Ligue no contexto quando Canais falha e repete apenas a leitura', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'creation', 'G02 requer o manifesto F1 de criação');
    const account = creationPreview.accounts.a;
    const currentAgent = creationAgent(account, 'pronto-para-ligar');
    const endpoint = channelsPath(account.id, currentAgent.id);
    let channelRequests = 0;
    let publishRequests = 0;

    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    page.on('request', currentRequest => {
      const path = requestPath(currentRequest);
      if (currentRequest.method() === 'GET' && path === endpoint)
        channelRequests += 1;
      if (
        currentRequest.method() === 'POST' &&
        path === `${agentPath(account.id, currentAgent.id)}/publish`
      ) {
        publishRequests += 1;
      }
    });

    await test.step('fault:ligue-canais-first-read', async () => {
      await page.route(
        `**${endpoint}`,
        route => route.abort('failed'),
        { times: 1 }
      );
    });
    await page.goto(creationPath(account.id, currentAgent.id, 'live'));
    await expect(page.getByTestId('creation-entry-error')).toBeVisible();
    await expect(
      page.locator('[data-action="creation-entry-retry"]')
    ).toBeVisible();
    await capture(page, testInfo, 'g02-ligue-canais-erro');

    await page.locator('[data-action="creation-entry-retry"]').click();
    await expect(page.getByTestId('agent-creation-live')).toBeVisible();
    await expect.poll(() => channelRequests).toBe(2);
    expect(publishRequests).toBe(0);
    await capture(page, testInfo, 'g02-ligue-canais-recuperado');
  });

  test('G03 marca uma única caixa, permite desmarcar e conserva seleção múltipla', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'creation', 'G03 requer o manifesto F1 de criação');
    const account = creationPreview.accounts.b;
    if (!account) {
      throw new Error(
        'F1 fixture account.b is required for the one-channel creation scenario'
      );
    }
    const currentAgent = creationAgent(account, 'one-channel-e4');
    await previewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    await page.goto(creationPath(account.id, currentAgent.id, 'live'));
    await expect(page.getByTestId('agent-creation-live')).toBeVisible();

    const available = page.locator(
      '[data-testid="agent-creation-live"] [data-channel-id]:not([disabled])'
    );
    await expect(available).toHaveCount(1);
    await expect(available.first()).toHaveAttribute('aria-checked', 'true');
    await available.first().click();
    await expect(available.first()).toHaveAttribute('aria-checked', 'false');
    await expect(page.getByTestId('creation-live-publish')).toBeDisabled();
    await capture(page, testInfo, 'g03-uma-caixa-desmarcada');

    const multipleAccount = creationPreview.accounts.a;
    const multipleAgent = creationAgent(
      multipleAccount,
      'pronto-para-ligar'
    );
    await page.goto(
      creationPath(multipleAccount.id, multipleAgent.id, 'live')
    );
    await expect(page.getByTestId('agent-creation-live')).toBeVisible();
    const multiple = page.locator(
      '[data-testid="agent-creation-live"] [data-channel-id]:not([disabled])'
    );
    expect(await multiple.count()).toBeGreaterThanOrEqual(2);
    await expect(multiple.nth(0)).toHaveAttribute('aria-checked', 'false');
    await expect(multiple.nth(1)).toHaveAttribute('aria-checked', 'false');
    await multiple.nth(0).click();
    await multiple.nth(1).click();
    await expect(multiple.nth(0)).toHaveAttribute('aria-checked', 'true');
    await expect(multiple.nth(1)).toHaveAttribute('aria-checked', 'true');
    await multiple.nth(0).click();
    await expect(multiple.nth(0)).toHaveAttribute('aria-checked', 'false');
    await expect(multiple.nth(1)).toHaveAttribute('aria-checked', 'true');
    await capture(page, testInfo, 'g03-multiplas-caixas');
  });

  test('G04 mostra confidence do backend separada do contador de materiais', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'gestao', 'G04 requer o manifesto GESTAO do painel');
    const account = gestaoPreview.accounts.a;
    const currentAgent = gestaoAgent(account, 'external');
    const { api } = await gestaoPreviewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    await page.goto(panelPath(account.id, currentAgent.id, 'knowledge'));
    const panel = page.getByTestId('agent-panel-knows');
    await expect(panel).toBeVisible();
    await expect(panel.getByTestId('knowledge-count')).toBeVisible();
    await expect(panel.getByTestId('knowledge-confidence')).toBeVisible();

    const agentPayload = await readJSON(
      await api.get(panelAgentPath(account.id, currentAgent.id))
    );
    const config = (agentPayload.config || {}) as JSONRecord;
    const confidence = Number(config.knowledge_confidence);
    expect(Number.isFinite(confidence)).toBe(true);
    const confidencePercent = Math.round(
      Math.max(0, Math.min(1, confidence)) * 100
    );

    const sourcesPayload = await readJSON(
      await api.get(`${panelAgentPath(account.id, currentAgent.id)}/sources`)
    );
    const sources = Array.isArray(sourcesPayload.payload)
      ? (sourcesPayload.payload as JSONRecord[])
      : [];
    const knowledgeCount = sources.filter(
      source => source.kind === 'knowledge'
    ).length;

    await expect(panel.getByTestId('knowledge-confidence')).toContainText(
      `${confidencePercent}%`
    );
    await expect(panel.getByTestId('knowledge-count')).toContainText(
      `${knowledgeCount} de 30 materiais`
    );
    await expect(panel.locator('[role="progressbar"]')).toHaveAttribute(
      'aria-label',
      'Confiança da base de conhecimento'
    );
    await expect(panel.locator('[role="progressbar"]')).toHaveAttribute(
      'aria-valuenow',
      String(confidencePercent)
    );
    await capture(
      page,
      testInfo,
      'g04-confidence-e-contador',
      '[data-testid="knowledge-confidence"]'
    );
  });

  test('G05 mantém a aba profunda visível em mount e routechange sem chamar focus', async (
    { page, request },
    testInfo
  ) => {
    test.skip(suite !== 'gestao', 'G05 requer o manifesto GESTAO do painel');
    await page.addInitScript(() => {
      const focusCalls = [] as string[];
      const originalFocus = HTMLElement.prototype.focus;
      HTMLElement.prototype.focus = function focus(options) {
        if (this.id.startsWith('agent-panel-tab-')) focusCalls.push(this.id);
        originalFocus.call(this, options);
      };
      (window as Window & { __agentPanelFocusCalls?: string[] }).__agentPanelFocusCalls =
        focusCalls;
    });

    const account = gestaoPreview.accounts.a;
    const currentAgent = gestaoAgent(account, 'external');
    await gestaoPreviewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });

    await page.goto(panelPath(account.id, currentAgent.id, 'channels'));
    await expect(page.getByTestId('agent-panel')).toBeVisible();
    await expect(page.locator('#agent-panel-tab-channels')).toHaveAttribute(
      'aria-selected',
      'true'
    );
    await assertActiveTabIsInsideTablist(page, 'channels');
    expect(
      await page.evaluate(
        () =>
          (window as Window & { __agentPanelFocusCalls?: string[] })
            .__agentPanelFocusCalls || []
      )
    ).toEqual([]);
    await capture(page, testInfo, 'g05-canais-mount', '[role="tablist"]');

    await page.locator('#agent-panel-tab-tune').click();
    await expect(page).toHaveURL(/\/tune$/);
    await expect(page.locator('#agent-panel-tab-tune')).toHaveAttribute(
      'aria-selected',
      'true'
    );
    await assertActiveTabIsInsideTablist(page, 'tune');
    expect(
      await page.evaluate(
        () =>
          (window as Window & { __agentPanelFocusCalls?: string[] })
            .__agentPanelFocusCalls || []
      )
    ).toEqual([]);
    await capture(page, testInfo, 'g05-ajustes-routechange', '[role="tablist"]');
  });
});
