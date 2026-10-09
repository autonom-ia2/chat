import {
  expect,
  test,
  type Locator,
  type Page,
  type TestInfo,
} from '@playwright/test';
import { expectNoSeriousA11y } from '../../helpers/expectNoSeriousA11y';
import {
  agentPath,
  createTransportLatch,
  gestaoPreviewSession,
  loadGestaoPreviewManifest,
  panelAgentPath,
  recordScreenshot,
  screenshotPath,
  type GestaoPreviewAccount,
  type GestaoPreviewAgent,
  type PreviewApi,
  type TransportScenario,
} from '../../fixtures/agents';

type GestaoManifest = Awaited<ReturnType<typeof loadGestaoPreviewManifest>>;

type JSONRecord = Record<string, unknown>;

let preview!: GestaoManifest;

test.beforeAll(async () => {
  preview = await loadGestaoPreviewManifest();
});

test.beforeEach(async ({ page }, testInfo) => {
  page.on('pageerror', error => {
    console.error(
      `[${testInfo.project.name}] browser pageerror: ${error.stack || error.message}`
    );
  });
});

const baseURL = () => {
  const value = process.env.AGENTS_PREVIEW_URL;
  if (!value) throw new Error('AGENTS_PREVIEW_URL is required');
  return value;
};

const accountA = () => preview.accounts.a;
const accountB = () => preview.accounts.b;

const fixtureAgent = (
  account: GestaoPreviewAccount,
  key: string
): GestaoPreviewAgent => {
  const currentAgent = account.agents[key];
  if (!currentAgent) throw new Error(`GESTAO fixture agent is missing: ${key}`);
  return currentAgent;
};

const panelPath = (accountId: number, agentId: number, tab = 'performance') =>
  `/app/accounts/${accountId}/agents/${agentId}/${tab}`;

const agentAPIPath = (accountId: number, agentId: number) =>
  panelAgentPath(accountId, agentId);

const sourcePath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/sources`;

const faqPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/faq_suggestions`;

const channelsPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/channels`;

const versionsPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/instruction_versions`;

const toolsPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/tools`;

const testPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/test`;

const avatarPath = (accountId: number, agentId: number) =>
  `${agentAPIPath(accountId, agentId)}/avatar`;

const RESYNC_FIXTURES: Record<string, string> = {
  'chromium-1440-light': 'resync_1440_light',
  'chromium-1440-dark': 'resync_1440_dark',
  'chromium-400-light': 'resync_400_light',
  'chromium-400-dark': 'resync_400_dark',
};

const resyncFixtureFor = (projectName: string) => {
  const fixture = RESYNC_FIXTURES[projectName];
  if (!fixture) {
    throw new Error(`GESTAO resync fixture is missing for ${projectName}`);
  }
  return fixture;
};

type NamedTestTransport = {
  name: string;
  status: number;
  body: JSONRecord;
};

const resultBody = ({
  reply,
  confidence = 0.8,
  handoff = { should: false, reason: null },
  skippedTools = [],
  usedKnowledge = [],
}: {
  reply: string;
  confidence?: number | null;
  handoff?: { should: boolean; reason: string | null };
  skippedTools?: Array<JSONRecord>;
  usedKnowledge?: Array<JSONRecord>;
}): JSONRecord => ({
  reply,
  confidence,
  handoff,
  answered_from_knowledge: usedKnowledge.length > 0,
  skipped_tools: skippedTools,
  writes_external: false,
  used_knowledge: usedKnowledge,
  humanized: false,
  chunks: [],
});

// Named responses are used only after the real local agent projection has
// loaded. The body follows playground/test.json.jbuilder.
const TEST_TRANSPORTS: Record<string, NamedTestTransport> = {
  internalHandoff: {
    name: 'internal_handoff_suppressed',
    status: 200,
    body: resultBody({
      reply: 'Resposta interna de exemplo.',
      confidence: 0.34,
      handoff: { should: true, reason: 'low_confidence' },
    }),
  },
  quote: {
    name: 'quote_test_result',
    status: 200,
    body: resultBody({
      reply: 'Posso continuar a cotação com os dados disponíveis.',
      confidence: 0.9,
      skippedTools: [
        {
          slug: 'consulta_exemplo',
          name: 'Consulta de exemplo',
          code: 'not_in_test',
        },
      ],
    }),
  },
  noResponse: {
    name: 'no_response',
    status: 200,
    body: resultBody({ reply: '', confidence: null }),
  },
  retrySuccess: {
    name: 'retry_success',
    status: 200,
    body: resultBody({ reply: 'Resposta após tentar novamente.' }),
  },
  rateLimited: {
    name: 'rate_limited',
    status: 429,
    body: { error: 'rate_limited', code: 'rate_limited' },
  },
  delayedSuccess: {
    name: 'delayed_retry_success',
    status: 200,
    body: resultBody({ reply: 'Resposta depois da nova tentativa.' }),
  },
  viewerSkippedTool: {
    name: 'viewer_tool_skipped',
    status: 200,
    body: resultBody({
      reply: 'Resposta sem executar a ferramenta.',
      skippedTools: [
        {
          slug: 'consulta_exemplo',
          name: 'Consulta de exemplo',
          code: 'viewer_not_allowed',
        },
      ],
    }),
  },
  knowledgeHandoff: {
    name: 'knowledge_handoff',
    status: 200,
    body: resultBody({
      reply: 'Encontrei uma informação, mas a equipe precisa continuar.',
      confidence: 0.28,
      handoff: { should: true, reason: 'low_confidence' },
      usedKnowledge: [
        {
          source: 'Manual de atendimento',
          content: 'Trecho usado na resposta de exemplo.',
        },
      ],
    }),
  },
};

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
  const file = await screenshotPath(
    testInfo.project.name,
    `gestao-${scenario}`
  );
  await page.screenshot({
    path: file,
    fullPage: false,
    animations: 'disabled',
  });
  await recordScreenshot({
    scenario: `gestao-${scenario}`,
    project: testInfo.project.name,
    file,
  });
  await expectNoSeriousA11y(page);
};

const openPanel = async ({
  page,
  request,
  account,
  role,
  fixture,
  tab = 'performance',
  scenario,
}: {
  page: Page;
  request: Parameters<typeof gestaoPreviewSession>[0]['request'];
  account: GestaoPreviewAccount;
  role: Parameters<typeof gestaoPreviewSession>[0]['role'];
  fixture: string;
  tab?: string;
  scenario?: TransportScenario;
}) => {
  const currentAgent = fixtureAgent(account, fixture);
  const session = await gestaoPreviewSession({
    page,
    request,
    account,
    role,
    baseURL: baseURL(),
    scenario,
  });
  await page.goto(panelPath(account.id, currentAgent.id, tab));
  await expect(page.getByTestId('agent-panel')).toBeVisible();
  return { api: session.api, currentAgent };
};

const settingsSection = (page: Page, key: string) =>
  page.locator(`[data-test="${key}"]`);

const field = (root: Page | Locator, key: string) =>
  root
    .locator(
      `input[data-test="${key}"], textarea[data-test="${key}"], [data-test="${key}"] input, [data-test="${key}"] textarea`
    )
    .first();

const requestFor = (page: Page, pathname: string, method: string) =>
  page.waitForRequest(
    request =>
      request.method() === method &&
      new URL(request.url()).pathname === pathname
  );

const responseFor = (page: Page, pathname: string, method: string) =>
  page.waitForResponse(
    response =>
      response.request().method() === method &&
      new URL(response.url()).pathname === pathname
  );

const waitForAgentRefresh = async (
  page: Page,
  refresh: ReturnType<typeof responseFor>
) => {
  const response = await refresh;
  await response.finished();
  // The network response can arrive before the fetch body reaches Vue and
  // before the prop watcher has rendered the refreshed form values.
  await page.evaluate(
    () =>
      new Promise<void>(resolve => {
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
      })
  );
  return response;
};

const patchFromUI = async ({
  page,
  pathname,
  body,
  trigger,
}: {
  page: Page;
  pathname: string;
  body: JSONRecord;
  trigger: () => Promise<void>;
}) => {
  const requestPromise = requestFor(page, pathname, 'PATCH');
  const responsePromise = responseFor(page, pathname, 'PATCH');
  await trigger();
  const [request, response] = await Promise.all([
    requestPromise,
    responsePromise,
  ]);
  expect(response.ok()).toBe(true);
  expect(request.postDataJSON()).toEqual(body);
};

const responseJSON = async (
  response: Awaited<ReturnType<PreviewApi['get']>>
) => {
  expect(response.ok()).toBe(true);
  return (await response.json()) as JSONRecord;
};

const loadRealAgentBeforeResultRoute = async ({
  api,
  account,
  currentAgent,
}: {
  api: PreviewApi;
  account: GestaoPreviewAccount;
  currentAgent: GestaoPreviewAgent;
}) => {
  const payload = await responseJSON(
    await api.get(agentAPIPath(account.id, currentAgent.id))
  );
  expect(payload.id).toBe(currentAgent.id);
};

const forceNamedTestTransport = async ({
  page,
  api,
  account,
  currentAgent,
  transport,
}: {
  page: Page;
  api: PreviewApi;
  account: GestaoPreviewAccount;
  currentAgent: GestaoPreviewAgent;
  transport: NamedTestTransport;
}) => {
  await loadRealAgentBeforeResultRoute({ api, account, currentAgent });
  expect(transport.name).toBeTruthy();
  await page.route(
    `**${testPath(account.id, currentAgent.id)}`,
    async route => {
      if (route.request().method() !== 'POST') {
        await route.continue();
        return;
      }
      await route.fulfill({
        status: transport.status,
        contentType: 'application/json',
        body: JSON.stringify(transport.body),
      });
    }
  );
};

test.describe('Gestão de agentes — jornadas reais no runtime GESTAO', () => {
  test('01 abre o painel externo, mostra as abas e mantém o foco visível', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
    });

    await expect(page.getByTestId('agent-panel-header')).toContainText(
      currentAgent.name
    );
    await expect(page.getByTestId('agent-panel-avatar')).toBeVisible();

    const expectedTabs = [
      'performance',
      'test',
      'knowledge',
      'channels',
      'tune',
    ];
    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await expect(tabs).toHaveCount(expectedTabs.length);
    for (const key of expectedTabs) {
      await expect(page.locator(`#agent-panel-tab-${key}`)).toBeVisible();
      await expect(page.locator(`#agent-panel-tab-${key}`)).toHaveAttribute(
        'aria-controls',
        `agent-panel-panel-${key}`
      );
    }

    const firstTab = page.locator('#agent-panel-tab-performance');
    const lastTab = page.locator(`#agent-panel-tab-${expectedTabs.at(-1)}`);
    await firstTab.focus();
    await firstTab.press('End');
    await expect(lastTab).toBeFocused();
    await lastTab.press('Home');
    await expect(firstTab).toBeFocused();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const tablist = document.querySelector('[role="tablist"]');
          const focused = document.activeElement;
          if (!tablist || !focused || !tablist.contains(focused)) return false;
          const listRect = tablist.getBoundingClientRect();
          const focusedRect = focused.getBoundingClientRect();
          return (
            focusedRect.left >= listRect.left - 1 &&
            focusedRect.right <= listRect.right + 1
          );
        })
      )
      .toBe(true);
    await capture(
      page,
      testInfo,
      '01-painel-abas',
      '#agent-panel-panel-performance'
    );
  });

  test('02 mostra os sete estados de material e não mistura a mídia de teste', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'knowledge',
    });
    const panel = page.getByTestId('agent-panel-knows');
    const cards = panel.getByTestId('knowledge-material');
    await expect(cards).toHaveCount(7);
    for (const state of [
      'uploading',
      'reading',
      'unreadable',
      'needs_another_file',
      'not_reviewed',
      'out_of_business_not_used',
      'ready',
    ]) {
      const stateCards = panel.locator(
        `[data-testid="knowledge-material"][data-state="${state}"]`
      );
      await expect(stateCards).toHaveCount(1);
    }
    await expect(
      cards.filter({ hasText: 'Imagem para enviar.png' })
    ).toHaveCount(0);
    await expect(panel.getByTestId('material-quality')).toContainText(
      'Nota 9,2 de 10'
    );
    await expect(panel.getByTestId('knowledge-count')).toContainText('7');
    await expect(panel).toContainText(currentAgent.name);
    await capture(
      page,
      testInfo,
      '02-conhecimento-estados',
      '[data-testid="agent-panel-knows"] [data-state="out_of_business_not_used"]'
    );
  });

  test('03 cobre o material fora do negócio usado e os limites vazio/30', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'knowledge_fallback',
      tab: 'knowledge',
    });
    const fallbackCard = page.getByTestId('knowledge-material').first();
    await expect(page.getByTestId('knowledge-material')).toHaveCount(1);
    await expect(fallbackCard).toHaveAttribute(
      'data-state',
      'out_of_business_used'
    );
    await expect(fallbackCard).toHaveAttribute('data-uses', 'true');
    await capture(
      page,
      testInfo,
      '03a-conhecimento-fallback',
      '[data-testid="agent-panel-knows"] [data-testid="knowledge-material"]'
    );

    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'knowledge_empty',
      tab: 'knowledge',
    });
    const emptyPanel = page.getByTestId('agent-panel-knows');
    const emptyMaterials = emptyPanel.locator(':scope > [data-state="empty"]');
    await expect(emptyMaterials).toHaveCount(1);
    await expect(emptyMaterials).toBeVisible();
    await expect(emptyPanel.getByTestId('knowledge-material')).toHaveCount(0);
    await expect(emptyPanel.getByTestId('knowledge-count')).toContainText('0');
    await expect(
      emptyPanel.locator('[data-action="add-material"]')
    ).toBeEnabled();
    await capture(
      page,
      testInfo,
      '03b-conhecimento-vazio',
      '[data-testid="agent-panel-knows"] > [data-state="empty"]'
    );

    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'knowledge_limit',
      tab: 'knowledge',
    });
    const limitPanel = page.getByTestId('agent-panel-knows');
    await expect(limitPanel.getByTestId('knowledge-count')).toContainText('30');
    await expect(limitPanel.getByTestId('knowledge-limit')).toBeVisible();
    await expect(
      limitPanel.locator('[data-action="add-material"]')
    ).toBeDisabled();
    await capture(
      page,
      testInfo,
      '03c-conhecimento-limite30',
      '[data-testid="knowledge-limit"]'
    );
  });

  test('04 mantém loading, erro de transporte e tentativa novamente em O que sabe', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    const latch = createTransportLatch();
    await gestaoPreviewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
      scenario: {
        kind: 'transport_delay',
        until: latch.until,
        matches: currentRequest =>
          new URL(currentRequest.url()).pathname ===
          sourcePath(account.id, currentAgent.id),
      },
    });
    const navigation = page.goto(
      panelPath(account.id, currentAgent.id, 'knowledge')
    );
    await expect(
      page.getByTestId('agent-panel-knows').getByRole('status')
    ).toBeVisible();
    await capture(
      page,
      testInfo,
      '04a-conhecimento-carregando',
      '[data-testid="agent-panel-knows"]'
    );
    latch.release();
    await navigation;
    await expect(page.getByTestId('knowledge-count')).toContainText('7');

    await page.route(
      `**${sourcePath(account.id, currentAgent.id)}`,
      route => route.abort('failed'),
      { times: 1 }
    );
    await page.reload();
    const knowledgeError = page
      .getByTestId('agent-panel-knows')
      .locator(':scope > [data-state="error"]');
    await expect(knowledgeError).toHaveCount(1);
    await expect(knowledgeError).toBeVisible();
    await capture(
      page,
      testInfo,
      '04b-conhecimento-erro',
      '[data-testid="agent-panel-knows"] > [data-state="error"]'
    );
    await page.locator('[data-action="retry-sources"]').click();
    await expect(page.getByTestId('knowledge-count')).toContainText('7');
  });

  test('05 adiciona um link válido e remove o material somente após confirmação', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'knowledge',
    });
    const link = 'https://materiais.example.invalid/pagina';
    const panel = page.getByTestId('agent-panel-knows');
    await panel.locator('[data-action="add-material"]').click();
    const addDialog = page.locator('dialog[open]').last();
    await expect(addDialog.getByTestId('add-material-dialog')).toBeVisible();
    await addDialog.locator('input[type="url"]').fill(link);
    await capture(
      page,
      testInfo,
      '05a-material-adicionar-dialog',
      '[data-testid="add-material-dialog"]'
    );
    const createResponse = responseFor(
      page,
      sourcePath(account.id, currentAgent.id),
      'POST'
    );
    const createRequest = requestFor(
      page,
      sourcePath(account.id, currentAgent.id),
      'POST'
    );
    await addDialog.getByRole('button').last().click();
    const [createdResponse, createdRequest] = await Promise.all([
      createResponse,
      createRequest,
    ]);
    expect(createdResponse.ok()).toBe(true);
    expect(createdRequest.postDataJSON()).toMatchObject({
      source: {
        source_type: 'link',
        reference: link,
        external_link: link,
        kind: 'knowledge',
      },
    });
    await expect(
      panel.getByTestId('knowledge-material').filter({ hasText: link })
    ).toBeVisible();

    const linkCard = panel
      .getByTestId('knowledge-material')
      .filter({ hasText: link });
    await linkCard.locator('[data-action="remove"]').click();
    const removeDialog = page.locator('dialog[open]').last();
    await expect(removeDialog).toContainText(link);
    await capture(
      page,
      testInfo,
      '05b-material-remover-dialog',
      'dialog[open]'
    );
    // Match the concrete source id without relying on a generated fixture id.
    const deleteResponse = page.waitForResponse(response => {
      const pathname = new URL(response.url()).pathname;
      return (
        response.request().method() === 'DELETE' &&
        pathname.startsWith(`${sourcePath(account.id, currentAgent.id)}/`)
      );
    });
    const deleteRequest = page.waitForRequest(
      currentRequest =>
        currentRequest.method() === 'DELETE' &&
        new URL(currentRequest.url()).pathname.startsWith(
          `${sourcePath(account.id, currentAgent.id)}/`
        )
    );
    await removeDialog.getByRole('button').last().click();
    const [removedRequest, removedResponse] = await Promise.all([
      deleteRequest,
      deleteResponse,
    ]);
    expect(removedRequest).toBeTruthy();
    expect(removedResponse.ok()).toBe(true);
    await expect(linkCard).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '05-material-link-remover',
      '[data-testid="knowledge-count"]'
    );
  });

  test('06 reenvia um material com falha pelo caminho real de resync', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const fixture = resyncFixtureFor(testInfo.project.name);
    const currentAgent = fixtureAgent(account, fixture);
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture,
      tab: 'knowledge',
    });
    const resyncCards = page.getByTestId('knowledge-material');
    await expect(resyncCards).toHaveCount(1);
    const resyncCard = resyncCards.first();
    const resyncButton = resyncCard.locator('[data-action="resync"]');
    await expect(resyncButton).toHaveCount(1);
    await expect(resyncButton).toBeEnabled();
    const state = await resyncCard.getAttribute('data-state');
    expect(['unreadable', 'needs_another_file', 'not_reviewed']).toContain(
      state
    );
    await capture(
      page,
      testInfo,
      '06a-material-resync-antes',
      '[data-action="resync"]'
    );

    const resyncResponse = page.waitForResponse(response => {
      const pathname = new URL(response.url()).pathname;
      return (
        response.request().method() === 'POST' &&
        pathname.startsWith(`${sourcePath(account.id, currentAgent.id)}/`) &&
        pathname.endsWith('/resync')
      );
    });
    const resyncRequest = page.waitForRequest(currentRequest => {
      const pathname = new URL(currentRequest.url()).pathname;
      return (
        currentRequest.method() === 'POST' &&
        pathname.startsWith(`${sourcePath(account.id, currentAgent.id)}/`) &&
        pathname.endsWith('/resync')
      );
    });
    await resyncButton.click();
    await resyncRequest;
    const response = await resyncResponse;
    expect([200, 201, 202]).toContain(response.status());
    await expect(resyncCard).toBeVisible();
    await capture(
      page,
      testInfo,
      '06b-material-resync-depois',
      '[data-testid="knowledge-material"]'
    );
  });

  test('07 pagina, edita, aprova, ignora e alterna as perguntas da equipe', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'knowledge',
    });
    const faq = page.getByTestId('faq-review');
    const sourcesBeforeApprovalPayload = await responseJSON(
      await api.get(sourcePath(account.id, currentAgent.id))
    );
    const sourcesBeforeApproval = Array.isArray(
      sourcesBeforeApprovalPayload.payload
    )
      ? (sourcesBeforeApprovalPayload.payload as Array<JSONRecord>)
      : [];
    const sourceIdsBeforeApproval = new Set(
      sourcesBeforeApproval.map(source => Number(source.id))
    );
    const pendingCount = Number(
      (await faq.getByTestId('faq-pending-count').textContent())?.trim()
    );
    expect(Number.isInteger(pendingCount)).toBe(true);
    expect(pendingCount).toBeGreaterThan(0);
    const initialCount = await faq.getByTestId('faq-suggestion').count();
    expect(initialCount).toBeGreaterThan(0);

    const loadMore = faq.locator('[data-action="load-more"]');
    await expect(loadMore).toBeVisible();
    const loadMoreResponse = responseFor(
      page,
      faqPath(account.id, currentAgent.id),
      'GET'
    );
    await loadMore.click();
    const response = await loadMoreResponse;
    expect(response.ok()).toBe(true);
    const pageTwo = (await response.json()) as JSONRecord;
    const pageTwoPayload = Array.isArray(pageTwo.payload)
      ? pageTwo.payload
      : [];
    expect(pageTwoPayload.length).toBeGreaterThan(0);
    await expect(faq.getByTestId('faq-suggestion')).toHaveCount(
      initialCount + pageTwoPayload.length
    );

    const edited = faq.getByTestId('faq-suggestion').first();
    await edited.locator('[data-action="edit-approve"]').click();
    await edited.locator('input').first().fill('Pergunta revisada na prévia');
    await edited
      .locator('textarea')
      .first()
      .fill('Resposta revisada na prévia');
    const approveResponse = page.waitForResponse(response => {
      const pathname = new URL(response.url()).pathname;
      return (
        response.request().method() === 'POST' && pathname.endsWith('/approve')
      );
    });
    await edited.locator('[data-action="save-approve"]').click();
    const approvedResponse = await approveResponse;
    expect(approvedResponse.ok()).toBe(true);
    expect(await approvedResponse.json()).toMatchObject({
      question: 'Pergunta revisada na prévia',
      answer: 'Resposta revisada na prévia',
      status: 'edited',
    });

    const ignored = faq.getByTestId('faq-suggestion').first();
    const ignoreResponse = page.waitForResponse(response => {
      const pathname = new URL(response.url()).pathname;
      return (
        response.request().method() === 'POST' && pathname.endsWith('/ignore')
      );
    });
    await ignored.locator('[data-action="ignore"]').click();
    expect((await ignoreResponse).ok()).toBe(true);

    // LabeledSwitch renders the test id on the switch button itself.
    const toggle = faq.getByTestId('faq-toggle');
    const turnOffResponse = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'PATCH'
    );
    await toggle.click();
    expect((await turnOffResponse).ok()).toBe(true);
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    await page.locator('#agent-panel-tab-test').click();
    await page.locator('#agent-panel-tab-knowledge').click();
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    const faqReadback = await responseJSON(
      await api.get(agentAPIPath(account.id, currentAgent.id))
    );
    expect((faqReadback.config as JSONRecord).faq_suggestions).toBe(false);
    const turnOnResponse = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'PATCH'
    );
    await toggle.click();
    expect((await turnOnResponse).ok()).toBe(true);
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    await capture(
      page,
      testInfo,
      '07-faq-paginacao-acoes',
      '[data-testid="faq-review"]'
    );

    const sourcesAfterApprovalPayload = await responseJSON(
      await api.get(sourcePath(account.id, currentAgent.id))
    );
    const sourcesAfterApproval = Array.isArray(
      sourcesAfterApprovalPayload.payload
    )
      ? (sourcesAfterApprovalPayload.payload as Array<JSONRecord>)
      : [];
    const faqSourcesCreatedByScenario = sourcesAfterApproval.filter(
      source =>
        source.reference === 'FAQ aprovadas' &&
        source.kind === 'knowledge' &&
        !sourceIdsBeforeApproval.has(Number(source.id))
    );
    expect(faqSourcesCreatedByScenario).toHaveLength(1);
    const faqSourceCreatedByScenario = faqSourcesCreatedByScenario[0];
    expect(faqSourceCreatedByScenario).toMatchObject({
      id: expect.any(Number),
      kind: 'knowledge',
      source_type: 'txt',
      reference: 'FAQ aprovadas',
      status: 'ready',
    });
    expect(
      (faqSourceCreatedByScenario.metadata as JSONRecord).chunk_count
    ).toBe(1);
    expect((faqSourceCreatedByScenario.review as JSONRecord).status).toBe(
      'accepted'
    );

    const removeFaqSourceResponse = await api.delete(
      `${sourcePath(account.id, currentAgent.id)}/${faqSourceCreatedByScenario.id}`
    );
    expect(removeFaqSourceResponse.status()).toBe(204);
    const sourcesAfterCleanupPayload = await responseJSON(
      await api.get(sourcePath(account.id, currentAgent.id))
    );
    const sourcesAfterCleanup = Array.isArray(
      sourcesAfterCleanupPayload.payload
    )
      ? (sourcesAfterCleanupPayload.payload as Array<JSONRecord>)
      : [];
    expect(
      sourcesAfterCleanup.map(source => Number(source.id)).sort((a, b) => a - b)
    ).toEqual([...sourceIdsBeforeApproval].sort((a, b) => a - b));
    expect(
      sourcesAfterCleanup.filter(source => source.kind === 'knowledge')
    ).toHaveLength(7);
  });

  test('08 conecta duas caixas, remove uma com confirmação e preserva erro sem projeção falsa', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'channels',
    });
    const channels = page.getByTestId('agent-panel-channels');
    await expect(channels.locator('[data-connected-channel]')).toHaveCount(2);
    const available = channels.getByRole('button', {
      name: `Colocar em ${account.inboxes.available.name}`,
      exact: true,
    });
    await expect(available).toHaveCount(1);
    const connectResponse = responseFor(
      page,
      channelsPath(account.id, currentAgent.id),
      'POST'
    );
    await available.click();
    expect((await connectResponse).status()).toBe(201);
    await expect(channels.locator('[data-connected-channel]')).toHaveCount(3);
    await capture(
      page,
      testInfo,
      '08a-canais-multiplos',
      '[data-testid="agent-panel-channels"]'
    );

    const added = channels.getByRole('button', {
      name: `Remover ${account.inboxes.available.name}`,
      exact: true,
    });
    await expect(added).toHaveCount(1);
    await added.click();
    const removeDialog = page.locator('dialog[open]').last();
    await expect(removeDialog).toContainText(account.inboxes.available.name);
    await capture(page, testInfo, '08b-canais-remover-dialog', 'dialog[open]');
    const removeResponse = responseFor(
      page,
      `${channelsPath(account.id, currentAgent.id)}/${account.inboxes.available.id}`,
      'DELETE'
    );
    await removeDialog.getByRole('button').last().click();
    expect((await removeResponse).status()).toBe(204);
    await expect(channels.locator('[data-connected-channel]')).toHaveCount(2);

    await page.route(
      `**${channelsPath(account.id, currentAgent.id)}`,
      async route => {
        if (route.request().method() === 'POST') {
          await route.fulfill({
            status: 422,
            contentType: 'application/json',
            body: JSON.stringify({ error: 'A caixa já está ocupada.' }),
          });
          return;
        }
        await route.continue();
      }
    );
    const second = channels
      .locator('[data-eligible-channel]')
      .filter({ hasText: account.inboxes.available_second.name });
    await second.locator('[data-action="channel-connect"]').click();
    await expect(channels.getByRole('alert')).toContainText(
      'A caixa já está ocupada.'
    );
    await expect(channels.locator('[data-connected-channel]')).toHaveCount(2);
    await page.unroute(`**${channelsPath(account.id, currentAgent.id)}`);
    await capture(
      page,
      testInfo,
      '08-canais-multiplos-erro',
      '[data-testid="agent-panel-channels"]'
    );
  });

  test('09 rascunho/pausado ficam sem conexão e o gerente sem inbox não recebe atalho', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'paused',
      tab: 'channels',
    });
    const pausedChannels = page
      .getByTestId('agent-panel-channels')
      .locator('[data-state="channel-inactive"]');
    await expect(pausedChannels).toHaveCount(1);
    await expect(pausedChannels).toBeVisible();
    await expect(
      page.locator('[data-action="channel-connect"]').first()
    ).toBeDisabled();
    await capture(
      page,
      testInfo,
      '09a-canais-pausado',
      '[data-testid="agent-panel-channels"] [data-state="channel-inactive"]'
    );

    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'draft',
      tab: 'channels',
    });
    const draftChannels = page
      .getByTestId('agent-panel-channels')
      .locator('[data-state="channel-inactive"]');
    await expect(draftChannels).toHaveCount(1);
    await expect(draftChannels).toBeVisible();
    await capture(
      page,
      testInfo,
      '09b-canais-rascunho',
      '[data-testid="agent-panel-channels"] [data-state="channel-inactive"]'
    );

    await openPanel({
      page,
      request,
      account,
      role: 'editor',
      fixture: 'external',
      tab: 'channels',
    });
    await expect(page.locator('[data-action="open-channels"]')).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '09c-canais-sem-permissao',
      '[data-testid="agent-panel-channels"]'
    );
  });

  test('10 quem só vê consegue testar sem ganhar controles de escrita', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'viewer',
      fixture: 'external',
      tab: 'test',
    });
    await expect(page.locator('#agent-panel-tab-performance')).toBeVisible();
    await expect(page.locator('#agent-panel-tab-test')).toBeVisible();
    await expect(page.locator('#agent-panel-tab-knowledge')).toHaveCount(0);
    await expect(page.locator('[data-action="test-teach"]')).toHaveCount(0);
    const question = 'Como funciona o atendimento?';
    await page.getByTestId('test-message').fill(question);
    await page
      .getByTestId('agent-panel-test-phone')
      .locator('[data-action="test-send"]')
      .click();
    await expect(page.getByRole('log')).toContainText(question);
    await expect(page.getByTestId('test-confidence')).toBeVisible();
    await capture(
      page,
      testInfo,
      '10-teste-viewer',
      '[data-testid="agent-test-legend"]'
    );
  });

  test('11 interno não mostra canais nem passagem para equipe e oculta saudação', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'internal',
      tab: 'test',
    });
    await expect(page.locator('#agent-panel-tab-channels')).toHaveCount(0);
    await expect(page.getByTestId('legend-handoff')).toHaveCount(0);
    await expect(page.getByTestId('test-handoff')).toHaveCount(0);
    await expect(page.getByTestId('agent-panel-test-phone')).toContainText(
      'Conversa de exemplo:'
    );
    await capture(
      page,
      testInfo,
      '11a-interno-teste',
      '[data-testid="agent-panel-test-phone"]'
    );

    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'internal',
      tab: 'tune',
    });
    await expect(
      settingsSection(page, 'settings-speech').locator(
        '[data-test="speech-greeting"]'
      )
    ).toHaveCount(0);
    await expect(settingsSection(page, 'settings-handoff')).toHaveCount(0);
    await expect(settingsSection(page, 'settings-audience')).toHaveCount(0);
    await expect(settingsSection(page, 'settings-schedule')).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '11b-interno-ajustes',
      '[data-test="settings-identity"]'
    );
  });

  test('12 both mantém canais e avisa que os ajustes de atendimento são para clientes', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'both',
      tab: 'tune',
    });
    await expect(settingsSection(page, 'both-notice')).toBeVisible();
    await expect(settingsSection(page, 'settings-handoff')).toBeVisible();
    await expect(settingsSection(page, 'settings-audience')).toBeVisible();
    await expect(settingsSection(page, 'settings-schedule')).toBeVisible();
    await expect(page.locator('#agent-panel-tab-channels')).toBeVisible();
    await capture(
      page,
      testInfo,
      '12-both-ajustes',
      '[data-test="both-notice"]'
    );
  });

  test('13 cotação mostra ramos próprios, aviso e escolhas sem materiais ou ferramentas', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'quote',
      tab: 'knowledge',
    });
    await expect(page.getByTestId('agent-quote-notice')).toBeVisible();
    await expect(page.getByTestId('agent-quote-knowledge')).toBeVisible();
    await expect(page.getByTestId('agent-panel-knows')).toHaveCount(0);
    await expect(page.locator('[data-testid="faq-review"]')).toHaveCount(0);
    await expect(page.locator('#agent-panel-tab-tools')).toHaveCount(0);

    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'quote',
      tab: 'tune',
    });
    await expect(settingsSection(page, 'settings-quote')).toBeVisible();
    await expect(settingsSection(page, 'settings-instructions')).toHaveCount(0);
    await expect(settingsSection(page, 'settings-versions')).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '13-cotacao-ramos-ajustes',
      '[data-test="settings-quote"]'
    );
  });

  test('14 salva identidade, voz e fala com payloads próprios e restaura o estado da fixture', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'tune',
    });
    const identity = settingsSection(page, 'settings-identity');
    await field(identity, 'identity-name').fill(
      `${currentAgent.name} temporária`
    );
    await identity.locator('[data-test="voice-masculina"]').click();
    const firstIdentityRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: { name: `${currentAgent.name} temporária`, voice: 'masculina' },
      },
      trigger: () => identity.locator('[data-test="identity-save"]').click(),
    });
    await waitForAgentRefresh(page, firstIdentityRefresh);
    await expect(field(identity, 'identity-name')).toHaveValue(
      `${currentAgent.name} temporária`
    );
    await expect(
      identity.locator('[data-test="voice-masculina"]')
    ).toHaveAttribute('aria-checked', 'true');
    await field(identity, 'identity-name').fill(currentAgent.name);
    await identity.locator('[data-test="voice-feminina"]').click();
    const secondIdentityRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: { agent: { name: currentAgent.name, voice: 'feminina' } },
      trigger: () => identity.locator('[data-test="identity-save"]').click(),
    });
    await waitForAgentRefresh(page, secondIdentityRefresh);
    await expect(field(identity, 'identity-name')).toHaveValue(
      currentAgent.name
    );
    await expect(
      identity.locator('[data-test="voice-feminina"]')
    ).toHaveAttribute('aria-checked', 'true');

    const speech = settingsSection(page, 'settings-speech');
    await field(speech, 'speech-greeting').fill('Cumprimento temporário.');
    await field(speech, 'speech-fallback').fill('Fallback temporário.');
    await field(speech, 'speech-tone').fill('Tom temporário, claro e simples.');
    const firstSpeechRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          greeting: 'Cumprimento temporário.',
          fallback_message: 'Fallback temporário.',
          tone: 'Tom temporário, claro e simples.',
        },
      },
      trigger: () => speech.locator('[data-test="speech-save"]').click(),
    });
    await waitForAgentRefresh(page, firstSpeechRefresh);
    await expect(field(speech, 'speech-greeting')).toHaveValue(
      'Cumprimento temporário.'
    );
    await expect(field(speech, 'speech-fallback')).toHaveValue(
      'Fallback temporário.'
    );
    await expect(field(speech, 'speech-tone')).toHaveValue(
      'Tom temporário, claro e simples.'
    );
    await field(speech, 'speech-greeting').fill('Olá! Como posso ajudar?');
    await field(speech, 'speech-fallback').fill('Vou chamar a equipe.');
    await field(speech, 'speech-tone').fill('Cordial, simples e direto');
    const secondSpeechRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          greeting: 'Olá! Como posso ajudar?',
          fallback_message: 'Vou chamar a equipe.',
          tone: 'Cordial, simples e direto',
        },
      },
      trigger: () => speech.locator('[data-test="speech-save"]').click(),
    });
    await waitForAgentRefresh(page, secondSpeechRefresh);
    await expect(field(speech, 'speech-greeting')).toHaveValue(
      'Olá! Como posso ajudar?'
    );
    await expect(field(speech, 'speech-fallback')).toHaveValue(
      'Vou chamar a equipe.'
    );
    await expect(field(speech, 'speech-tone')).toHaveValue(
      'Cordial, simples e direto'
    );
    await capture(
      page,
      testInfo,
      '14-ajustes-identidade-fala',
      '[data-test="settings-speech"]'
    );
  });

  test('15 salva alvo, público e horário em seções independentes', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'tune',
    });
    const handoff = settingsSection(page, 'settings-handoff');
    await expect
      .poll(() => handoff.locator('[data-test="handoff-target"]').count())
      .toBe(0);
    await handoff.locator('[data-test="target-member"]').click();
    const target = handoff.locator('[data-test="handoff-target"]');
    await expect(target.getByRole('combobox')).toBeVisible();
    await target.getByRole('combobox').click();
    const memberOption = page.getByRole('option').first();
    const memberId = Number(await memberOption.getAttribute('data-value'));
    await memberOption.click();
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          config: {
            handoff_strategy: 'low_confidence',
            handoff_target_type: 'member',
            handoff_target_id: memberId,
          },
        },
      },
      trigger: () => handoff.locator('[data-test="handoff-save"]').click(),
    });
    await capture(
      page,
      testInfo,
      '15a-ajustes-encaminhamento',
      '[data-test="settings-handoff"]'
    );
    await handoff.locator('[data-test="target-any"]').click();
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          config: {
            handoff_strategy: 'low_confidence',
            handoff_target_type: 'any',
            handoff_target_id: null,
          },
        },
      },
      trigger: () => handoff.locator('[data-test="handoff-save"]').click(),
    });

    const audience = settingsSection(page, 'settings-audience');
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          config: { audience: null, audience_unknown_contact: 'respond' },
        },
      },
      trigger: () => audience.getByRole('button').last().click(),
    });
    await capture(
      page,
      testInfo,
      '15b-ajustes-publico',
      '[data-test="settings-audience"]'
    );

    const schedule = settingsSection(page, 'settings-schedule');
    const scheduleLinks = schedule.locator('[data-test="schedule-inbox-link"]');
    await expect(scheduleLinks).toHaveCount(2);
    for (const inbox of [account.inboxes.primary, account.inboxes.secondary]) {
      const link = scheduleLinks.filter({ hasText: inbox.name });
      await expect(link).toHaveAttribute(
        'href',
        `/app/accounts/${account.id}/settings/inboxes/${inbox.id}/business-hours`
      );
    }
    await schedule.locator('#business_hours').click();
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: { agent: { config: { response_window: 'business_hours' } } },
      trigger: () => schedule.getByRole('button').last().click(),
    });
    await capture(
      page,
      testInfo,
      '15c-ajustes-horario',
      '[data-test="settings-schedule"]'
    );
    await schedule.locator('#always').click();
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: { agent: { config: { response_window: 'always' } } },
      trigger: () => schedule.getByRole('button').last().click(),
    });
  });

  test('16 guarda manual vazio somente depois de texto e volta para a versão guiada sem expor seu texto', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'manual',
      tab: 'tune',
    });
    await expect(
      field(
        settingsSection(page, 'settings-instructions'),
        'manual-instruction'
      )
    ).toHaveValue(
      'Responda com o texto que eu escrevi: atendimento de exemplo.'
    );

    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'tune',
    });
    const instructions = settingsSection(page, 'settings-instructions');
    const manualField = field(instructions, 'manual-instruction');
    if ((await manualField.count()) === 0) {
      await instructions.locator('[data-test="open-manual"]').click();
      await capture(page, testInfo, '16a-manual-confirmacao', 'dialog[open]');
      await page
        .locator('dialog[open]')
        .locator('[data-test="confirm-manual"]')
        .click();
    }
    await expect(field(instructions, 'manual-instruction')).toHaveValue('');
    await field(instructions, 'manual-instruction').fill(
      'Instrução manual temporária da prévia.'
    );
    await patchFromUI({
      page,
      pathname: agentAPIPath(account.id, currentAgent.id),
      body: {
        agent: {
          mode: 'manual',
          instruction: 'Instrução manual temporária da prévia.',
        },
      },
      trigger: () => instructions.locator('[data-test="save-manual"]').click(),
    });

    const versionsPayload = await responseJSON(
      await api.get(versionsPath(account.id, currentAgent.id))
    );
    const versions = (versionsPayload.payload || []) as Array<JSONRecord>;
    const guidedVersion = versions.find(version => version.origin === 'guided');
    expect(guidedVersion?.id).toEqual(expect.any(Number));
    expect(guidedVersion?.instruction).toBeUndefined();
    expect(
      await settingsSection(page, 'settings-versions').textContent()
    ).not.toContain('GUIADA_NAO_EXIBIR');

    const restoreButton = page.locator(
      `[data-test="restore-version-${guidedVersion?.id}"]`
    );
    await expect(restoreButton).toBeVisible();
    await restoreButton.click();
    await capture(page, testInfo, '16b-guiada-confirmacao', 'dialog[open]');
    await page
      .locator('dialog[open]')
      .locator('[data-test="confirm-restore"]')
      .click();
    await expect(
      instructions.locator('[data-test="manual-instruction"]')
    ).toHaveCount(0);
    await expect(
      instructions.locator('[data-test="reconverse"]')
    ).toBeVisible();
    const restoredVersionsPayload = await responseJSON(
      await api.get(versionsPath(account.id, currentAgent.id))
    );
    const restoredVersions =
      restoredVersionsPayload.payload as Array<JSONRecord>;
    const currentVersions = restoredVersions.filter(version => version.current);
    expect(currentVersions).toHaveLength(1);
    const currentRestore = page.locator(
      `[data-test="restore-version-${currentVersions[0].id}"]`
    );
    await expect(currentRestore).toBeDisabled();
    await expect(currentRestore.locator('..')).toContainText('Atual');
    await capture(
      page,
      testInfo,
      '16-ajustes-manual-guiado',
      '[data-test="settings-versions"]'
    );
  });

  test('17 salva as escolhas de cotação no endpoint próprio', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'quote');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'quote',
      tab: 'tune',
    });
    const quote = settingsSection(page, 'settings-quote');
    await quote.locator('#quote-objetivo').click();
    await field(quote, 'quote-schedule').fill('Segunda a sexta, das 8h às 17h');
    const quotePath = `${agentAPIPath(account.id, currentAgent.id)}/quote_choices`;
    const firstQuoteRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: quotePath,
      body: {
        behavior: 'objetivo',
        horario: 'Segunda a sexta, das 8h às 17h',
      },
      trigger: () => quote.locator('[data-test="quote-save"]').click(),
    });
    await waitForAgentRefresh(page, firstQuoteRefresh);
    await expect(field(quote, 'quote-schedule')).toHaveValue(
      'Segunda a sexta, das 8h às 17h'
    );
    await expect(quote.locator('#quote-objetivo')).toBeChecked();
    await quote.locator('#quote-consultivo').click();
    await field(quote, 'quote-schedule').fill('Segunda a sexta, das 9h às 18h');
    const secondQuoteRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await patchFromUI({
      page,
      pathname: quotePath,
      body: {
        behavior: 'consultivo',
        horario: 'Segunda a sexta, das 9h às 18h',
      },
      trigger: () => quote.locator('[data-test="quote-save"]').click(),
    });
    await waitForAgentRefresh(page, secondQuoteRefresh);
    await expect(field(quote, 'quote-schedule')).toHaveValue(
      'Segunda a sexta, das 9h às 18h'
    );
    await expect(quote.locator('#quote-consultivo')).toBeChecked();
    await capture(
      page,
      testInfo,
      '17-cotacao-escolhas',
      '[data-test="settings-quote"]'
    );
  });

  test('18 pausa e ativa com confirmação, sem excluir o agente', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'paused');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'paused',
      tab: 'tune',
    });
    const lifecycle = settingsSection(page, 'settings-lifecycle');
    await expect(
      lifecycle.locator('[data-test="activate-agent"]')
    ).toBeVisible();
    await lifecycle.locator('[data-test="activate-agent"]').click();
    await expect(page.locator('dialog[open]')).toContainText(currentAgent.name);
    await capture(
      page,
      testInfo,
      '18a-ciclo-ativar-confirmacao',
      'dialog[open]'
    );
    const activateRequest = requestFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'PATCH'
    );
    await page
      .locator('dialog[open]')
      .locator('[data-test="confirm-lifecycle"]')
      .click();
    const activated = await activateRequest;
    expect(activated.postDataJSON()).toEqual({
      agent: { status: 'active', enabled: true },
    });
    await expect(lifecycle.locator('[data-test="pause-agent"]')).toBeVisible();

    await lifecycle.locator('[data-test="pause-agent"]').click();
    await expect(page.locator('dialog[open]')).toContainText(currentAgent.name);
    await capture(
      page,
      testInfo,
      '18b-ciclo-pausar-confirmacao',
      'dialog[open]'
    );
    const pauseRequest = requestFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'PATCH'
    );
    await page
      .locator('dialog[open]')
      .locator('[data-test="confirm-lifecycle"]')
      .click();
    const paused = await pauseRequest;
    expect(paused.postDataJSON()).toEqual({
      agent: { status: 'paused', enabled: false },
    });
  });

  test('19 SuperAdmin testa parâmetro, preserva segredo mascarado e faz CRUD de ferramenta', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'super_admin',
      fixture: 'external',
      tab: 'tools',
    });
    const tools = page.locator('[data-test="panel-tools-v2"]');
    const seededCard = tools.locator('article').first();
    const testButton = seededCard.locator('[data-test^="tool-test-"]');
    const testId = (await testButton.getAttribute('data-test'))?.replace(
      'tool-test-',
      ''
    );
    expect(testId).toBeTruthy();

    await seededCard.locator(`[data-test="tool-edit-${testId}"]`).click();
    const editDialog = page.locator('dialog[open]').last();
    await expect(
      editDialog.locator('[data-test="header-value-0"] input')
    ).toHaveValue('••••••••');
    await capture(
      page,
      testInfo,
      '19a-ferramenta-editar-dialog',
      'dialog[open]'
    );
    const maskedUpdate = requestFor(
      page,
      `${toolsPath(account.id, currentAgent.id)}/${testId}`,
      'PATCH'
    );
    await editDialog.locator('[data-test="tool-save"]').click();
    const maskedRequest = await maskedUpdate;
    const maskedBody = maskedRequest.postDataJSON() as JSONRecord;
    expect(JSON.stringify(maskedBody)).not.toContain('••••••••');
    expect(JSON.stringify(maskedBody)).not.toContain('preview-ficticio');
    await expect(editDialog).not.toBeVisible();

    await seededCard.locator(`[data-test="tool-edit-${testId}"]`).click();
    const maskedReadback = page.locator('dialog[open]').last();
    await expect(
      maskedReadback.locator('[data-test="header-value-0"] input')
    ).toHaveValue('••••••••');
    await maskedReadback.locator('[data-test="tool-cancel"]').click();

    await seededCard.locator(`[data-test="tool-test-${testId}"]`).click();
    const testDialog = page.locator('dialog[open]').last();
    await testDialog
      .locator('[data-test="test-param-codigo"] input')
      .fill('ABC-123');
    await capture(
      page,
      testInfo,
      '19b-ferramenta-testar-dialog',
      'dialog[open]'
    );
    const toolTestResponse = responseFor(
      page,
      `${toolsPath(account.id, currentAgent.id)}/${testId}/test`,
      'POST'
    );
    await testDialog.locator('[data-test="test-run"]').click();
    expect((await toolTestResponse).ok()).toBe(true);
    await expect(seededCard.locator('[data-test="tool-result"]')).toBeVisible();

    const newName = 'Ferramenta criada na prévia';
    await tools.locator('[data-test="new-tool"]').click();
    const createDialog = page.locator('dialog[open]').last();
    await createDialog.locator('[data-test="tool-name"] input').fill(newName);
    await createDialog
      .locator('[data-test="tool-slug"] input')
      .fill('ferramenta_preview');
    await createDialog
      .locator('[data-test="tool-when"] textarea')
      .fill('Consulta fictícia para a prévia.');
    await createDialog
      .locator('[data-test="tool-url"] input')
      .fill('https://tools.example.invalid/novo');
    await capture(
      page,
      testInfo,
      '19c-ferramenta-criar-dialog',
      'dialog[open]'
    );
    const createToolResponse = responseFor(
      page,
      toolsPath(account.id, currentAgent.id),
      'POST'
    );
    await createDialog.locator('[data-test="tool-save"]').click();
    expect((await createToolResponse).ok()).toBe(true);
    const newCard = tools.locator('article').filter({ hasText: newName });
    await expect(newCard).toBeVisible();
    const newId = (
      await newCard
        .locator('[data-test^="tool-delete-"]')
        .getAttribute('data-test')
    )?.replace('tool-delete-', '');
    expect(newId).toBeTruthy();

    await newCard.locator(`[data-test="tool-edit-${newId}"]`).click();
    const updateDialog = page.locator('dialog[open]').last();
    await updateDialog
      .locator('[data-test="tool-when"] textarea')
      .fill('Descrição alterada na prévia.');
    const updateToolResponse = responseFor(
      page,
      `${toolsPath(account.id, currentAgent.id)}/${newId}`,
      'PATCH'
    );
    await updateDialog.locator('[data-test="tool-save"]').click();
    expect((await updateToolResponse).ok()).toBe(true);
    await expect(newCard).toContainText('Descrição alterada na prévia.');

    await newCard.locator(`[data-test="tool-delete-${newId}"]`).click();
    await capture(
      page,
      testInfo,
      '19d-ferramenta-excluir-dialog',
      'dialog[open]'
    );
    const deleteToolResponse = page.waitForResponse(response => {
      const pathname = new URL(response.url()).pathname;
      return (
        response.request().method() === 'DELETE' &&
        pathname.endsWith(`/${newId}`)
      );
    });
    await page
      .locator('dialog[open]')
      .last()
      .locator('[data-test="delete-confirm"]')
      .click();
    expect((await deleteToolResponse).ok()).toBe(true);
    await expect(newCard).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '19-ferramentas-superadmin',
      '[data-test="panel-tools-v2"]'
    );
  });

  test('20 envia imagem no teste e mostra resposta com metadados do servidor', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    const imageInput = page
      .getByTestId('agent-panel-test-phone')
      .locator('input[type="file"]');
    await imageInput.setInputFiles({
      name: 'comprovante.png',
      mimeType: 'image/png',
      buffer: Buffer.from('fake-png-preview'),
    });
    const question = 'O que este material explica?';
    await page.getByTestId('test-message').fill(question);
    const testRequest = requestFor(
      page,
      testPath(account.id, currentAgent.id),
      'POST'
    );
    await page
      .getByTestId('agent-panel-test-phone')
      .locator('[data-action="test-send"]')
      .click();
    const postedTestRequest = await testRequest;
    const body = postedTestRequest.postDataJSON() as JSONRecord;
    expect(body.message).toBe(question);
    expect(body.images).toEqual([expect.stringContaining('data:image/png')]);
    await expect(page.getByRole('log')).toContainText(question);
    await expect(page.getByTestId('test-confidence')).toBeVisible();
    await capture(
      page,
      testInfo,
      '20-teste-imagem-metadados',
      '[data-testid="test-confidence"]'
    );
  });

  test('21 limpar conversa invalida resposta atrasada e não deixa balão tardio', async ({
    page,
    request,
  }) => {
    const account = accountA();
    const currentAgent = fixtureAgent(account, 'external');
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    const latch = createTransportLatch();
    const routePattern = `**${testPath(account.id, currentAgent.id)}`;
    await page.route(routePattern, async route => {
      await latch.until;
      try {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            payload: {
              reply: 'resposta tardia que não deve aparecer',
              confidence: 0.99,
            },
          }),
        });
      } catch {
        // Clearing the composer aborts the browser request; a late provider
        // result is intentionally allowed to lose its route here.
      }
    });
    await page.getByTestId('test-message').fill('Pergunta que será cancelada');
    await page
      .getByTestId('agent-panel-test-phone')
      .locator('[data-action="test-send"]')
      .click();
    await expect(page.getByTestId('agent-panel-test')).toHaveAttribute(
      'aria-busy',
      'true'
    );
    await page.locator('[data-action="test-clear"]').click();
    await expect(page.getByRole('log')).not.toContainText(
      'Pergunta que será cancelada'
    );
    latch.release();
    await page.unroute(routePattern);
    await expect(page.getByRole('log')).not.toContainText(
      'resposta tardia que não deve aparecer'
    );
  });

  test('23 interno não exibe amarelo de passagem mesmo quando o DTO sinaliza equipe', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'internal',
      tab: 'test',
    });
    await forceNamedTestTransport({
      page,
      api,
      account,
      currentAgent,
      transport: TEST_TRANSPORTS.internalHandoff,
    });
    const phone = page.getByTestId('agent-panel-test-phone');
    await phone
      .getByTestId('test-message')
      .fill('Dê um resumo desta conversa.');
    await phone.locator('[data-action="test-send"]').click();
    await expect(page.getByRole('log')).toContainText(
      'Resposta interna de exemplo.'
    );
    await expect(phone.getByTestId('test-handoff')).toHaveCount(0);
    await expect(page.getByTestId('legend-handoff')).toHaveCount(0);
    await capture(
      page,
      testInfo,
      '23a-teste-interno-sem-amarelo',
      '[data-testid="agent-panel-test-phone"]'
    );
  });

  test('24 cotação mostra o aviso próprio e não oferece passagem para equipe', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'quote',
      tab: 'test',
    });
    await forceNamedTestTransport({
      page,
      api,
      account,
      currentAgent,
      transport: TEST_TRANSPORTS.quote,
    });
    const phone = page.getByTestId('agent-panel-test-phone');
    await expect(phone.getByTestId('quote-test-notice')).toHaveCount(0);
    await phone.getByTestId('test-message').fill('Quero simular uma cotação.');
    await phone.locator('[data-action="test-send"]').click();
    await expect(page.getByRole('log')).toContainText(
      'Posso continuar a cotação com os dados disponíveis.'
    );
    await expect(phone.getByTestId('test-handoff')).toHaveCount(0);
    await expect(phone.getByTestId('quote-test-notice')).toHaveCount(1);
    await expect(phone.getByTestId('quote-test-notice')).toContainText(
      'não consulta as seguradoras'
    );
    await capture(
      page,
      testInfo,
      '23b-teste-cotacao-aviso',
      '[data-testid="quote-test-notice"]'
    );
  });

  test('25 mostra o estado montando para um agente sem instrução pronta', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'draft',
      tab: 'test',
    });
    const testPanel = page.getByTestId('agent-panel-test');
    await expect(testPanel.locator('[data-state="assembling"]')).toBeVisible();
    await expect(testPanel).toContainText(
      'Este agente ainda está sendo montado.'
    );
    await capture(
      page,
      testInfo,
      '23c-teste-montando',
      '[data-state="assembling"]'
    );
  });

  test('26 permite tentar novamente quando o agente não responde', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    await loadRealAgentBeforeResultRoute({ api, account, currentAgent });
    let attempts = 0;
    const routePattern = `**${testPath(account.id, currentAgent.id)}`;
    await page.route(routePattern, async route => {
      if (route.request().method() !== 'POST') {
        await route.continue();
        return;
      }
      attempts += 1;
      const transport =
        attempts === 1
          ? TEST_TRANSPORTS.noResponse
          : TEST_TRANSPORTS.retrySuccess;
      await route.fulfill({
        status: transport.status,
        contentType: 'application/json',
        body: JSON.stringify(transport.body),
      });
    });

    const phone = page.getByTestId('agent-panel-test-phone');
    await phone.getByTestId('test-message').fill('Pergunta sem resposta.');
    await phone.locator('[data-action="test-send"]').click();
    const testPanel = page.getByTestId('agent-panel-test');
    await expect(testPanel.getByRole('alert')).toBeVisible();
    await expect(testPanel.locator('[data-action="test-retry"]')).toBeVisible();
    await capture(
      page,
      testInfo,
      '23d-teste-sem-resposta',
      '[data-action="test-retry"]'
    );

    await testPanel.locator('[data-action="test-retry"]').click();
    await expect(page.getByRole('log')).toContainText(
      'Resposta após tentar novamente.'
    );
    expect(attempts).toBe(2);
  });

  test('27 mostra limite temporário e bloqueia o novo envio após resposta 429', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    await forceNamedTestTransport({
      page,
      api,
      account,
      currentAgent,
      transport: TEST_TRANSPORTS.rateLimited,
    });
    const phone = page.getByTestId('agent-panel-test-phone');
    await phone.getByTestId('test-message').fill('Teste com limite.');
    await phone.locator('[data-action="test-send"]').click();
    const testPanel = page.getByTestId('agent-panel-test');
    await expect(
      testPanel.locator('[data-state="rate-limited"]')
    ).toBeVisible();
    await expect(phone.locator('[data-action="test-send"]')).toBeDisabled();
    await capture(
      page,
      testInfo,
      '23e-teste-rate-limit',
      '[data-state="rate-limited"]'
    );
  });

  test('28 sinaliza demora após 180 segundos e permite repetir sem esperar três minutos', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    await loadRealAgentBeforeResultRoute({ api, account, currentAgent });
    const latch = createTransportLatch();
    let attempts = 0;
    const routePattern = `**${testPath(account.id, currentAgent.id)}`;
    await page.route(routePattern, async route => {
      if (route.request().method() !== 'POST') {
        await route.continue();
        return;
      }
      attempts += 1;
      if (attempts === 1) {
        await latch.until;
        try {
          await route.fulfill({
            status: TEST_TRANSPORTS.delayedSuccess.status,
            contentType: 'application/json',
            body: JSON.stringify(TEST_TRANSPORTS.delayedSuccess.body),
          });
        } catch {
          // The delayed browser request is aborted when the user retries.
        }
        return;
      }
      await route.fulfill({
        status: TEST_TRANSPORTS.delayedSuccess.status,
        contentType: 'application/json',
        body: JSON.stringify(TEST_TRANSPORTS.delayedSuccess.body),
      });
    });

    await page.clock.install();
    const phone = page.getByTestId('agent-panel-test-phone');
    await phone.getByTestId('test-message').fill('Pergunta que demora.');
    await phone.locator('[data-action="test-send"]').click();
    await expect(page.getByTestId('agent-panel-test')).toHaveAttribute(
      'aria-busy',
      'true'
    );
    await page.clock.fastForward(180_000);
    const testPanel = page.getByTestId('agent-panel-test');
    await expect(testPanel.locator('[data-state="delayed"]')).toBeVisible();
    await capture(
      page,
      testInfo,
      '23f-teste-demora-180s',
      '[data-state="delayed"]'
    );

    await testPanel.locator('[data-action="test-retry"]').click();
    await expect(page.getByRole('log')).toContainText(
      'Resposta depois da nova tentativa.'
    );
    await expect.poll(() => attempts).toBe(2);
    latch.release();
    await page.unroute(routePattern);
  });

  test('29 visualizador vê a ferramenta pulada sem receber permissão de execução', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'viewer',
      fixture: 'external',
      tab: 'test',
    });
    await forceNamedTestTransport({
      page,
      api,
      account,
      currentAgent,
      transport: TEST_TRANSPORTS.viewerSkippedTool,
    });
    const phone = page.getByTestId('agent-panel-test-phone');
    await phone.getByTestId('test-message').fill('Consulte o dado disponível.');
    await phone.locator('[data-action="test-send"]').click();
    await expect(page.getByRole('log')).toContainText(
      'Resposta sem executar a ferramenta.'
    );
    await expect(phone).toContainText('Consulta de exemplo');
    await capture(
      page,
      testInfo,
      '23g-teste-ferramenta-pulada-viewer',
      '[data-testid="test-confidence"]'
    );
  });

  test('30 exibe material usado e passagem amarela para a equipe', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'test',
    });
    await forceNamedTestTransport({
      page,
      api,
      account,
      currentAgent,
      transport: TEST_TRANSPORTS.knowledgeHandoff,
    });
    const phone = page.getByTestId('agent-panel-test-phone');
    await phone
      .getByTestId('test-message')
      .fill('Use o manual e encaminhe se necessário.');
    await phone.locator('[data-action="test-send"]').click();
    await expect(phone.getByTestId('test-used-material')).toContainText(
      'Manual de atendimento'
    );
    await expect(phone.getByTestId('test-handoff')).toHaveAttribute(
      'data-state',
      'handoff'
    );
    await capture(
      page,
      testInfo,
      '23h-teste-material-handoff',
      '[data-testid="test-handoff"]'
    );
  });

  test('31 salva avatar, confirma leitura na API e restaura a fixture sem imagem', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api, currentAgent } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      tab: 'tune',
    });

    const initialDelete = await api.delete(
      avatarPath(account.id, currentAgent.id)
    );
    expect(initialDelete.ok()).toBe(true);
    await page.reload();
    const identity = settingsSection(page, 'settings-identity');
    const imageInput = identity.locator('input[type="file"]');
    await expect(imageInput).toHaveCount(1);
    const previewPng = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      'base64'
    );
    const uploadResponse = responseFor(
      page,
      avatarPath(account.id, currentAgent.id),
      'PATCH'
    );
    const agentRefresh = responseFor(
      page,
      agentAPIPath(account.id, currentAgent.id),
      'GET'
    );
    await imageInput.setInputFiles({
      name: 'avatar-preview.png',
      mimeType: 'image/png',
      buffer: previewPng,
    });
    const uploaded = await uploadResponse;
    expect(uploaded.ok()).toBe(true);
    await waitForAgentRefresh(page, agentRefresh);
    const uploadedPayload = (await uploaded.json()) as JSONRecord;
    expect(uploadedPayload.avatar_url).toEqual(expect.any(String));
    expect(String(uploadedPayload.avatar_url)).not.toBe('');

    const readback = await responseJSON(
      await api.get(agentAPIPath(account.id, currentAgent.id))
    );
    expect(readback.avatar_url).toBe(uploadedPayload.avatar_url);
    const avatarImage = identity.locator('img').first();
    await expect(avatarImage).toBeVisible();
    await expect
      .poll(() =>
        avatarImage.evaluate((image: HTMLImageElement) => image.complete)
      )
      .toBe(true);
    await expect
      .poll(() =>
        avatarImage.evaluate((image: HTMLImageElement) => image.naturalWidth)
      )
      .toBeGreaterThan(0);
    await capture(
      page,
      testInfo,
      '23i-ajustes-avatar',
      '[data-test="settings-identity"]'
    );

    let removeButton = identity.getByRole('button', { name: 'Tirar foto' });
    if ((await removeButton.count()) === 0) {
      removeButton = identity.getByRole('button', { name: 'Remove photo' });
    }
    await expect(removeButton).toBeVisible();
    const removeResponse = responseFor(
      page,
      avatarPath(account.id, currentAgent.id),
      'DELETE'
    );
    await removeButton.click();
    const removed = await removeResponse;
    expect(removed.ok()).toBe(true);
    const removedPayload = await responseJSON(
      await api.get(agentAPIPath(account.id, currentAgent.id))
    );
    expect(removedPayload.avatar_url || '').toBe('');
  });

  test('22 mantém o isolamento entre contas no endpoint e na tela', async ({
    page,
    request,
  }) => {
    const account = accountB();
    const accountAData = accountA();
    const foreign = fixtureAgent(account, 'foreign');
    const session = await gestaoPreviewSession({
      page,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
    });
    const ownBeforeCrossAccountResponse = await session.api.get(
      agentPath(account.id, foreign.id)
    );
    expect(ownBeforeCrossAccountResponse.status()).toBe(200);
    const ownBeforeCrossAccountPayload =
      (await ownBeforeCrossAccountResponse.json()) as JSONRecord;
    expect(ownBeforeCrossAccountPayload.id).toBe(foreign.id);

    const crossAccountResponse = await session.api.get(
      agentPath(accountAData.id, fixtureAgent(accountAData, 'external').id)
    );
    expect(crossAccountResponse.status()).toBe(401);
    expect(await crossAccountResponse.json()).toEqual({
      error: 'You are not authorized to access this account',
    });

    const ownAfterCrossAccountResponse = await session.api.get(
      agentPath(account.id, foreign.id)
    );
    expect(ownAfterCrossAccountResponse.status()).toBe(200);
    const ownAfterCrossAccountPayload =
      (await ownAfterCrossAccountResponse.json()) as JSONRecord;
    expect(ownAfterCrossAccountPayload.id).toBe(foreign.id);

    await page.goto(panelPath(account.id, foreign.id));
    await expect(page.getByTestId('agent-panel')).toBeVisible();
    await expect(page.getByTestId('agent-panel-header')).toContainText(
      foreign.name
    );
    await expect(page.getByTestId('agent-panel-header')).not.toContainText(
      fixtureAgent(accountAData, 'external').name
    );
  });
});
