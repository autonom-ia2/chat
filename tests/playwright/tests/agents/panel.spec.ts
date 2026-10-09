import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { expectNoSeriousA11y } from '../../helpers/expectNoSeriousA11y';
import {
  panelAnalyticsConversationsPath,
  panelAnalyticsPath,
  panelAgentPath,
  loadPanelPreviewManifest,
  panelPreviewSession,
  recordScreenshot,
  screenshotPath,
  type PanelPreviewAccount,
  type PanelPreviewAgent,
  type PanelPreviewRole,
  type PreviewApi,
  createTransportLatch,
} from '../../fixtures/agents';

type PanelManifest = Awaited<ReturnType<typeof loadPanelPreviewManifest>>;
type AnalyticsPayload = {
  range: '7d' | '30d';
  conversations_handled: number;
  replies_sent: number;
  handoff_count: number;
  handoff_rate: number;
  avg_confidence: number | null;
  knowledge_answer_rate: number | null;
  timeline: Array<{ date: string; replies: number; handoffs: number }>;
  outcomes: Record<string, number>;
};
type DrawerPayload = {
  meta: {
    metric: string;
    range: '7d' | '30d';
    limit: number;
    count: number;
    has_hidden: boolean;
    has_more: boolean;
    hidden_count?: number;
    total_count?: number;
  };
  payload: Array<{
    report_id?: number;
    conversation_id?: number;
    message?: string;
    report_reason?: string;
    reason_label?: string;
    suggested_answer?: string | null;
    conversation?: {
      id: number;
      display_id: number;
      inbox_id: number;
      status: string;
    };
  }>;
};

const OUTCOMES = [
  'handled',
  'resolved_without_human',
  'handed_off',
  'reopened',
  'wrong_replies',
] as const;

const REPORT_REASONS = [
  'incorrect_information',
  'inappropriate_response',
  'incomplete_response',
  'outdated_information',
  'other',
] as const;

let preview!: PanelManifest;

test.beforeAll(async () => {
  preview = await loadPanelPreviewManifest();
});

const baseURL = () => {
  const value = process.env.AGENTS_PREVIEW_URL;
  if (!value) throw new Error('AGENTS_PREVIEW_URL is required');
  return value;
};

const accountA = () => preview.accounts.a;
const accountB = () => preview.accounts.b;

const agent = (
  account: PanelPreviewAccount,
  key: string
): PanelPreviewAgent => {
  const fixture = account.agents[key];
  if (!fixture) throw new Error(`F4 fixture agent is missing: ${key}`);
  return fixture;
};

const panelPath = (accountId: number, agentId: number) =>
  `/app/accounts/${accountId}/agents/${agentId}/performance`;

const tab = (page: Page, key: string) =>
  page.locator(`#agent-panel-tab-${key}`);

const outcome = (page: Page, key: string) =>
  page.getByTestId(`agent-outcome-${key}`);

const expectNoHorizontalOverflow = async (page: Page) => {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
};

const capture = async (page: Page, testInfo: TestInfo, name: string) => {
  await expectNoHorizontalOverflow(page);
  const file = await screenshotPath(testInfo.project.name, `panel-${name}`);
  await page.screenshot({
    path: file,
    fullPage: false,
    animations: 'disabled',
  });
  await recordScreenshot({
    scenario: `panel-${name}`,
    project: testInfo.project.name,
    file,
  });
  await expectNoSeriousA11y(page);
};

const responseJSON = async <T>(
  response: Awaited<ReturnType<PreviewApi['get']>>
) => {
  expect(response.ok()).toBe(true);
  return (await response.json()) as T;
};

const openPanel = async ({
  page,
  request,
  account,
  role,
  fixture,
  scenario,
}: {
  page: Page;
  request: Parameters<typeof panelPreviewSession>[0]['request'];
  account: PanelPreviewAccount;
  role: PanelPreviewRole;
  fixture: string;
  scenario?: Parameters<typeof panelPreviewSession>[0]['scenario'];
}) => {
  const currentAgent = agent(account, fixture);
  const session = await panelPreviewSession({
    page,
    request,
    account,
    role,
    baseURL: baseURL(),
    scenario,
  });
  await page.goto(panelPath(account.id, currentAgent.id));
  await expect(page.getByTestId('agent-panel')).toBeVisible();
  return { api: session.api, currentAgent };
};

const expectAnalyticsEnvelope = (
  payload: AnalyticsPayload,
  range: '7d' | '30d'
) => {
  expect(payload.range).toBe(range);
  expect(payload.timeline).toHaveLength(range === '7d' ? 7 : 30);
  expect(
    payload.timeline.every(point => /^\d{4}-\d{2}-\d{2}$/.test(point.date))
  ).toBe(true);
  for (const key of OUTCOMES)
    expect(payload.outcomes[key]).toEqual(expect.any(Number));
};

test.describe('F4 painel — jornadas reais e contrato de analytics', () => {
  test('mostra o cabeçalho, as abas normativas e o foco de teclado', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
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
    await expect(page.getByTestId('agent-panel-state')).toBeVisible();

    const expectedTabs = [
      'performance',
      'test',
      'knowledge',
      'channels',
      'tune',
    ];
    for (const key of expectedTabs) await expect(tab(page, key)).toBeVisible();
    await expect(tab(page, 'tools')).toHaveCount(0);
    await expect(page.locator('[role="tabpanel"]')).toHaveCount(1);

    for (const key of expectedTabs) {
      const currentTab = tab(page, key);
      await expect(currentTab).toHaveAttribute('aria-controls');
      await expect(currentTab).toHaveAttribute('role', 'tab');
    }

    const firstTab = tab(page, expectedTabs[0]);
    const lastTab = tab(page, expectedTabs.at(-1) || expectedTabs[0]);
    await firstTab.focus();
    await firstTab.press('End');
    await expect(lastTab).toBeFocused();
    await lastTab.press('Home');
    await expect(firstTab).toBeFocused();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const tablist = document.querySelector('[role="tablist"]');
          const first = document.querySelector('#agent-panel-tab-performance');
          if (!tablist || !first) return false;

          const tablistRect = tablist.getBoundingClientRect();
          const firstRect = first.getBoundingClientRect();
          return (
            firstRect.left >= tablistRect.left - 1 &&
            firstRect.right <= tablistRect.right + 1
          );
        })
      )
      .toBe(true);
    await expect(page.getByTestId('agent-external-summary')).toBeVisible();
    await capture(page, testInfo, 'external-cabecalho-abas');
  });

  test('SuperAdmin vê Ferramentas, mas a Lia não recebe essa aba', async ({
    page,
    request,
  }) => {
    const account = accountA();
    await openPanel({
      page,
      request,
      account,
      role: 'super_admin',
      fixture: 'external',
    });
    await expect(tab(page, 'tools')).toBeVisible();

    await page.goto(panelPath(account.id, agent(account, 'quote').id));
    await expect(page.getByTestId('agent-panel')).toBeVisible();
    await expect(page.getByTestId('agent-quote-notice')).toBeVisible();
    await expect(tab(page, 'knowledge')).toBeVisible();
    await expect(tab(page, 'tools')).toHaveCount(0);
    await expect(page.getByTestId('agent-materials')).toHaveCount(0);
  });

  test('editor consulta o painel da própria conta sem ganhar Ferramentas', async ({
    page,
    request,
  }) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'editor',
      fixture: 'external',
    });

    const response = await api.get(
      panelAnalyticsPath(account.id, currentAgent.id)
    );
    expect(response.ok()).toBe(true);
    await expect(tab(page, 'performance')).toBeVisible();
    await expect(tab(page, 'tools')).toHaveCount(0);
  });

  test('carrega 7 dias, troca para 30 dias e renderiza os cinco resultados reais', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
    });

    const initial = await responseJSON<AnalyticsPayload>(
      await api.get(panelAnalyticsPath(account.id, currentAgent.id))
    );
    expectAnalyticsEnvelope(initial, '7d');
    await expect(page.getByTestId('agent-performance')).toBeVisible();
    await expect(page.getByTestId('agent-timeline')).toHaveAttribute(
      'role',
      'img'
    );
    for (const key of OUTCOMES) {
      await expect(outcome(page, key)).toBeVisible();
      await expect(
        outcome(page, key).getByTestId('agent-outcome-count')
      ).toHaveText(String(initial.outcomes[key]));
    }

    const rangeResponse = page.waitForResponse(response => {
      const url = new URL(response.url());
      return (
        response.request().method() === 'GET' &&
        url.pathname === panelAnalyticsPath(account.id, currentAgent.id) &&
        url.searchParams.get('range') === '30d'
      );
    });
    await page.getByTestId('agent-analytics-range-30d').click();
    const thirtyDays = await responseJSON<AnalyticsPayload>(
      await rangeResponse
    );
    expectAnalyticsEnvelope(thirtyDays, '30d');
    await expect(page.getByTestId('agent-analytics-range-30d')).toHaveAttribute(
      'aria-pressed',
      'true'
    );
    await expect(
      page
        .getByTestId('agent-outcome-handled')
        .getByTestId('agent-outcome-count')
    ).toHaveText(String(thirtyDays.outcomes.handled));
    const summary = page.getByTestId('agent-external-summary');
    await expect(summary).toBeVisible();
    await expect(summary).toContainText(
      `${Math.round(Number(thirtyDays.handoff_rate) * 100)}%`
    );
    await expect(summary).toContainText(`(${thirtyDays.handoff_count})`);
    await expect(summary).toContainText('% que passaram para a equipe');
    await expect(summary).toContainText('% que usaram seus materiais');
    await expect(
      page.getByRole('heading', {
        name: 'Resultado das conversas',
        exact: true,
      })
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Dia a dia', exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole('heading', {
        name: 'Por que passou para a equipe',
        exact: true,
      })
    ).toBeVisible();
    const timeline = page.locator('[data-timeline-scroll]');
    const timelineBars = page.getByTestId('agent-timeline').getByRole('img');
    await expect(timelineBars).toHaveCount(30);
    await expect(timelineBars.first()).toHaveAttribute(
      'aria-label',
      /\d{2}\/\d{2}/
    );
    await expect(timelineBars.last()).toHaveAttribute(
      'aria-label',
      /\d{2}\/\d{2}/
    );
    await expect
      .poll(
        async () => {
          const [scrollBox, lastBar] = await Promise.all([
            timeline.boundingBox(),
            timelineBars.last().boundingBox(),
          ]);
          if (!scrollBox || !lastBar) return false;
          return (
            lastBar.x >= scrollBox.x - 1 &&
            lastBar.x + lastBar.width <= scrollBox.x + scrollBox.width + 1
          );
        },
        {
          message:
            'A barra mais recente dos 30 dias deve estar visível no gráfico',
        }
      )
      .toBe(true);
    if (await page.evaluate(() => window.innerWidth >= 1024)) {
      const [scrollBox, firstBar, lastBar] = await Promise.all([
        timeline.boundingBox(),
        timelineBars.first().boundingBox(),
        timelineBars.last().boundingBox(),
      ]);
      expect(scrollBox).not.toBeNull();
      expect(firstBar).not.toBeNull();
      expect(lastBar).not.toBeNull();
      if (scrollBox && firstBar && lastBar) {
        expect(firstBar.x).toBeGreaterThanOrEqual(scrollBox.x - 1);
        expect(firstBar.x + firstBar.width).toBeLessThanOrEqual(
          scrollBox.x + scrollBox.width + 1
        );
        expect(lastBar.x).toBeGreaterThanOrEqual(scrollBox.x - 1);
        expect(lastBar.x + lastBar.width).toBeLessThanOrEqual(
          scrollBox.x + scrollBox.width + 1
        );
      }
    }
    await capture(page, testInfo, 'external-desempenho-30d');

    const panelScroller = page.locator('[role="tabpanel"]');
    await timeline.scrollIntoViewIfNeeded();
    await expect(timeline).toBeInViewport();
    await capture(page, testInfo, 'external-desempenho-detalhes-30d');
    await panelScroller.evaluate(element => {
      element.scrollTo({ top: 0, left: 0, behavior: 'auto' });
    });
  });

  test('mostra vazio da semana, dados no mês e vazio total sem inventar métricas', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'week_empty',
    });
    const week = await responseJSON<AnalyticsPayload>(
      await api.get(
        panelAnalyticsPath(account.id, agent(account, 'week_empty').id)
      )
    );
    expectAnalyticsEnvelope(week, '7d');
    expect(Object.values(week.outcomes).every(value => value === 0)).toBe(true);
    await expect(page.getByTestId('agent-performance-empty')).toContainText(
      'Sem dados'
    );
    await capture(page, testInfo, 'desempenho-vazio-semana');

    await page.getByTestId('agent-analytics-range-30d').click();
    await expect(page.getByTestId('agent-performance')).toBeVisible();
    await expect(page.getByTestId('agent-performance-empty')).toHaveCount(0);
    await capture(page, testInfo, 'desempenho-semana-30d');

    await page.goto(panelPath(account.id, agent(account, 'month_empty').id));
    await expect(page.getByTestId('agent-performance-empty')).toContainText(
      'Sem dados'
    );
    const monthResponse = page.waitForResponse(response => {
      const url = new URL(response.url());
      return (
        response.request().method() === 'GET' &&
        url.pathname ===
          panelAnalyticsPath(account.id, agent(account, 'month_empty').id) &&
        url.searchParams.get('range') === '30d'
      );
    });
    await page.getByTestId('agent-analytics-range-30d').click();
    const month = await responseJSON<AnalyticsPayload>(await monthResponse);
    expectAnalyticsEnvelope(month, '30d');
    expect(Object.values(month.outcomes).every(value => value === 0)).toBe(
      true
    );
    await expect(page.getByTestId('agent-analytics-range-30d')).toHaveAttribute(
      'aria-pressed',
      'true'
    );
    const totalEmpty = page.getByTestId('agent-performance-empty');
    await expect(totalEmpty).toHaveAttribute('data-state', 'empty-total');
    await expect(totalEmpty.locator('[data-action="open-test"]')).toContainText(
      'Testar'
    );
    await capture(page, testInfo, 'desempenho-vazio-total');
  });

  test('abre a gaveta dos cinco resultados, respeita limite 50, foco e Escape', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
    });

    for (const metric of OUTCOMES) {
      const expected = await responseJSON<DrawerPayload>(
        await api.get(
          panelAnalyticsConversationsPath(account.id, currentAgent.id) +
            `?range=7d&metric=${metric}`
        )
      );
      const card = outcome(page, metric);
      await card.focus();
      const responsePromise = page.waitForResponse(response => {
        const url = new URL(response.url());
        return (
          response.request().method() === 'GET' &&
          url.pathname ===
            panelAnalyticsConversationsPath(account.id, currentAgent.id) &&
          url.searchParams.get('metric') === metric
        );
      });
      await card.click();
      await responsePromise;
      const drawer = page.getByTestId('agent-conversations-drawer');
      await expect(drawer).toBeVisible();
      const rows = drawer.getByTestId('agent-conversation-row');
      await expect(rows).toHaveCount(Math.min(expected.payload.length, 50));
      await expect(drawer.getByTestId('agent-drawer-period')).toContainText(
        '7 dias'
      );
      if (expected.meta.has_more) {
        await expect(drawer.getByTestId('agent-drawer-has-more')).toContainText(
          '50'
        );
      }
      if (expected.payload[0]?.conversation?.display_id) {
        const displayId = expected.payload[0].conversation.display_id;
        await expect(rows.first()).toHaveAttribute(
          'data-conversation-display-id',
          String(displayId)
        );
        await expect(
          rows.first().getByTestId('agent-conversation-open')
        ).toHaveAttribute(
          'href',
          new RegExp(`/accounts/${account.id}/conversations/${displayId}`)
        );
      }
      if (metric === 'handled') {
        expect(expected.meta.count).toBe(55);
        expect(expected.payload).toHaveLength(50);
        expect(expected.meta.has_more).toBe(true);
        expect(expected.payload[0]?.conversation?.status).toBe('open');
        await expect(rows.first()).toContainText('Aberta');
        await expect(rows.first()).not.toContainText(/(?:CRM|AGENTS)\./);
        await capture(page, testInfo, 'gaveta-atendidas-aberta');
      }
      await drawer.getByTestId('agent-drawer-close').focus();
      await page.keyboard.press('Escape');
      await expect(drawer).toBeHidden();
      await expect(card).toBeFocused();
    }

    await capture(page, testInfo, 'gaveta-resultados-fechada');
  });

  test('expõe os cinco motivos de resposta errada e a ação Ensinar com permissão', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const { api } = await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
    });
    const response = await responseJSON<DrawerPayload>(
      await api.get(
        panelAnalyticsConversationsPath(account.id, currentAgent.id) +
          '?range=30d&metric=wrong_replies'
      )
    );
    expect(response.meta.has_hidden).toBe(false);
    expect(response.payload.map(row => row.report_reason)).toEqual(
      expect.arrayContaining(REPORT_REASONS)
    );

    await page.getByTestId('agent-analytics-range-30d').click();
    await expect(page.getByTestId('agent-outcome-wrong_replies')).toBeVisible();
    await page.getByTestId('agent-outcome-wrong_replies').click();
    const drawer = page.getByTestId('agent-conversations-drawer');
    await expect(drawer).toBeVisible();
    await expect(drawer.getByTestId('agent-wrong-reason')).toHaveCount(
      response.payload.length
    );
    await expect(drawer.getByTestId('agent-wrong-teach')).toHaveCount(
      response.payload.length
    );
    for (const reason of REPORT_REASONS) {
      await expect(
        drawer.locator(`[data-report-reason="${reason}"]`)
      ).toHaveCount(1);
    }
    await capture(page, testInfo, 'gaveta-respostas-erradas');
    await drawer.getByTestId('agent-wrong-teach').first().click();
    await expect
      .poll(() => new URL(page.url()).pathname)
      .toBe(`/app/accounts/${account.id}/agents/${currentAgent.id}/knowledge`);
  });

  test('mantém o escopo de conversa para participante, viewer e outra conta', async ({
    page,
    request,
  }) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const participantSession = await panelPreviewSession({
      page,
      request,
      account,
      role: 'participant',
      baseURL: baseURL(),
    });
    const participantResponse = await responseJSON<DrawerPayload>(
      await participantSession.api.get(
        panelAnalyticsConversationsPath(account.id, currentAgent.id) +
          '?range=30d&metric=handled'
      )
    );
    expect(participantResponse.meta.count).toBe(1);
    expect(participantResponse.meta.has_hidden).toBe(true);
    expect(JSON.stringify(participantResponse)).not.toContain(
      'hidden-by-permission'
    );

    await page.goto(panelPath(account.id, currentAgent.id));
    await expect(page.getByTestId('agent-panel')).toBeVisible();
    await page.getByTestId('agent-analytics-range-30d').click();
    await page.getByTestId('agent-outcome-handled').click();
    await expect(page.getByTestId('agent-conversations-drawer')).toBeVisible();
    await expect(page.getByTestId('agent-drawer-has-hidden')).toContainText(
      'Algumas conversas'
    );

    const noPermissionSession = await panelPreviewSession({
      page,
      request,
      account,
      role: 'participant_no_perm',
      baseURL: baseURL(),
    });
    const noPermissionResponse = await responseJSON<DrawerPayload>(
      await noPermissionSession.api.get(
        panelAnalyticsConversationsPath(account.id, currentAgent.id) +
          '?range=30d&metric=handled'
      )
    );
    expect(noPermissionResponse.meta.count).toBe(0);
    expect(noPermissionResponse.meta.has_hidden).toBe(true);
    expect(noPermissionResponse.payload).toEqual([]);

    const foreignResponse = await noPermissionSession.api.get(
      panelAnalyticsPath(account.id, agent(accountB(), 'foreign').id)
    );
    expect(foreignResponse.status()).toBe(404);
  });

  test('viewer só consulta Como está indo e Testar, sem ações de escrita', async ({
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
    });
    await expect(tab(page, 'performance')).toBeVisible();
    await expect(tab(page, 'test')).toBeVisible();
    await expect(page.locator('[role="tab"]')).toHaveCount(2);
    await expect(page.getByTestId('agent-panel-action-pause')).toHaveCount(0);
    await expect(page.getByTestId('agent-panel-action-activate')).toHaveCount(
      0
    );
    await expect(page.getByTestId('agent-panel-action-edit')).toHaveCount(0);
    await expect(page.getByTestId('agent-wrong-teach')).toHaveCount(0);
    await capture(page, testInfo, 'viewer-somente-leitura');
  });

  test('não busca analytics para interno, mantém resumo externo no both e restringe abas da Lia', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const analyticsRequests: string[] = [];
    page.on('request', requestEvent => {
      if (new URL(requestEvent.url()).pathname.includes('/analytics')) {
        analyticsRequests.push(requestEvent.url());
      }
    });
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'internal',
    });
    await expect(page.getByTestId('agent-internal-summary')).toBeVisible();
    await expect(tab(page, 'channels')).toHaveCount(0);
    await expect.poll(() => analyticsRequests.length).toBe(0);
    await capture(page, testInfo, 'agente-interno');

    const bothAnalyticsResponse = page.waitForResponse(response => {
      const url = new URL(response.url());
      return (
        response.request().method() === 'GET' &&
        url.pathname ===
          panelAnalyticsPath(account.id, agent(account, 'both').id)
      );
    });
    await page.goto(panelPath(account.id, agent(account, 'both').id));
    const bothAnalytics = await bothAnalyticsResponse;
    expect(bothAnalytics.ok()).toBe(true);
    expectAnalyticsEnvelope(
      (await bothAnalytics.json()) as AnalyticsPayload,
      '7d'
    );
    await expect(page.getByTestId('agent-performance')).toBeVisible();
    await expect(page.getByTestId('agent-performance-empty')).toBeVisible();
    await expect(page.getByTestId('agent-internal-summary')).toHaveCount(0);

    await page.goto(panelPath(account.id, agent(account, 'quote').id));
    await expect(page.getByTestId('agent-quote-notice')).toBeVisible();
    await expect(tab(page, 'knowledge')).toBeVisible();
    await expect(tab(page, 'tools')).toHaveCount(0);
    await expect(page.getByTestId('agent-materials')).toHaveCount(0);
    await capture(page, testInfo, 'agente-cotacao');
  });

  test('editor vê os ramos da Cotação pela projeção do agente sem abrir a área de Seguros', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'quote');
    const session = await panelPreviewSession({
      page,
      request,
      account,
      role: 'editor',
      baseURL: baseURL(),
    });

    const detail = await responseJSON<{
      quote_branches: Array<{ slug: string; name: string }>;
    }>(await session.api.get(panelAgentPath(account.id, currentAgent.id)));
    expect(detail.quote_branches).toEqual([
      { slug: 'cotacao_auto', name: 'Cotação de automóvel' },
    ]);

    const insuranceRequests: string[] = [];
    page.on('request', requestEvent => {
      const pathname = new URL(requestEvent.url()).pathname;
      if (pathname.includes('/autonomia/insurance/')) {
        insuranceRequests.push(pathname);
      }
    });

    const insuranceGate = await session.api.get(
      `/api/v1/accounts/${account.id}/autonomia/insurance/quote_agent`
    );
    expect(insuranceGate.status()).toBe(401);

    await page.goto(
      `/app/accounts/${account.id}/agents/${currentAgent.id}/knowledge`
    );
    const knowledge = page.getByTestId('agent-quote-knowledge');
    await expect(knowledge).toBeVisible();
    await expect(
      knowledge.getByText('Cotação de automóvel', { exact: true })
    ).toBeVisible();
    expect(insuranceRequests).toEqual([]);
    await capture(page, testInfo, 'agente-cotacao-conhecimento');
  });

  test('mostra estado atendendo, pausado e rascunho sem mudar dados', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    for (const [fixture, state, action] of [
      ['external', 'Atendendo', 'pause'],
      ['paused', 'Pausado', 'activate'],
      ['draft', 'Falta terminar', 'continue'],
    ] as const) {
      await openPanel({
        page,
        request,
        account,
        role: 'admin',
        fixture,
      });
      await expect(page.getByTestId('agent-panel-state')).toContainText(state);
      const visibleAction = page.locator(
        `[data-testid="agent-panel-action-${action}"]:visible, ` +
          '[data-action="toggle-status-mobile"]:visible'
      );
      await expect(visibleAction).toHaveCount(1);
      await expect(visibleAction).toBeVisible();
      if (fixture !== 'draft') {
        const expectedChecked = fixture === 'external' ? 'true' : 'false';
        const expectedLabel = `${state}: ${agent(account, fixture).name}`;
        const stateSwitch = page.getByRole('switch', {
          name: expectedLabel,
          exact: true,
        });
        await expect(stateSwitch).toHaveCount(1);
        await expect(stateSwitch).toBeVisible();
        await expect(stateSwitch).toHaveAttribute(
          'aria-checked',
          expectedChecked
        );
      }
      await capture(page, testInfo, `agente-${fixture}-estado`);
    }
  });

  test('mostra carregamento e erro apenas por transporte local nomeado', async ({
    page,
    request,
  }, testInfo) => {
    const account = accountA();
    const currentAgent = agent(account, 'external');
    const latch = createTransportLatch();
    await openPanel({
      page,
      request,
      account,
      role: 'admin',
      fixture: 'external',
      scenario: {
        kind: 'transport_delay',
        until: latch.until,
        matches: requestEvent =>
          new URL(requestEvent.url()).pathname ===
          panelAnalyticsPath(account.id, currentAgent.id),
      },
    });
    await expect(page.getByTestId('agent-performance-loading')).toBeVisible();
    await capture(page, testInfo, 'desempenho-carregando');
    latch.release();
    await expect(page.getByTestId('agent-performance')).toBeVisible();

    const errorPage = await page.context().newPage();
    await panelPreviewSession({
      page: errorPage,
      request,
      account,
      role: 'admin',
      baseURL: baseURL(),
      scenario: {
        kind: 'provider_error',
        matches: requestEvent =>
          new URL(requestEvent.url()).pathname ===
          panelAnalyticsPath(account.id, currentAgent.id),
      },
    });
    await errorPage.goto(panelPath(account.id, currentAgent.id));
    await expect(
      errorPage.getByTestId('agent-performance-error')
    ).toBeVisible();
    await expect(errorPage.getByRole('alert')).toBeVisible();
    await expect(
      errorPage.getByTestId('agent-performance-retry')
    ).toBeVisible();
    await capture(errorPage, testInfo, 'desempenho-erro');
    const retryRequest = errorPage.waitForRequest(requestEvent => {
      const url = new URL(requestEvent.url());
      return (
        requestEvent.method() === 'GET' &&
        url.pathname === panelAnalyticsPath(account.id, currentAgent.id)
      );
    });
    await errorPage.getByTestId('agent-performance-retry').click();
    await retryRequest;
    await expect(
      errorPage.getByTestId('agent-performance-error')
    ).toBeVisible();
    await errorPage.close();
  });
});
