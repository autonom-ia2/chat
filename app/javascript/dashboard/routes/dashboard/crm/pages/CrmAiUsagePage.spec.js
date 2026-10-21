import { flushPromises, mount } from '@vue/test-utils';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CrmAiUsageAPI from 'dashboard/api/crmAiUsage';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { withFullI18n } from 'test-i18n';
import CrmAiUsagePage from './CrmAiUsagePage.vue';

// The global setup registers an empty i18n instance; this spec asserts on
// translated copy, so load the real messages (see vitest.setup.js).
withFullI18n();

const emitterHandlers = {};

vi.mock('dashboard/api/crmAiUsage', () => ({
  default: {
    get: vi.fn(),
    export: vi.fn(),
  },
}));

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getReportAiVsHuman: vi.fn() },
}));

vi.mock('dashboard/composables/emitter', () => ({
  useEmitter: vi.fn((event, handler) => {
    emitterHandlers[event] = handler;
  }),
}));

vi.mock('shared/components/charts/BarChart.vue', () => ({
  default: {
    name: 'BarChart',
    props: {
      data: {
        type: Object,
        default: () => ({}),
      },
    },
    template:
      '<div data-test-id="bar-chart">{{ data.categories.join(",") }}</div>',
  },
}));

const makePayload = (overrides = {}) => ({
  account: { id: 85, name: 'Autonom.ia' },
  com_valores: true,
  period: {
    since: '2026-06-21T12:00:00Z',
    until: '2026-06-28T12:00:00Z',
    group_by: 'day',
  },
  exchange_rate: {
    pair: 'USD-BRL',
    rate: 5.5,
    fetched_at: '2026-06-28T11:00:00Z',
    rate_unavailable: false,
  },
  totals: {
    usage_count: 2,
    period_spend: { cost_usd: 22.445455, cost_brl: 123.45 },
    average_cost: { cost_usd: 11.222727, cost_brl: 61.725 },
    cache_savings: { cost_usd: 1, cost_brl: 5.5 },
    cache_savings_pct: 4.27,
  },
  spend_by_resource: [
    {
      resource: 'Assistente de respostas',
      usage_count: 1,
      input_tokens: 100,
      cached_tokens: 20,
      output_tokens: 30,
      cost_usd: 10,
      cost_brl: 55,
    },
    {
      resource: 'Base de conhecimento',
      usage_count: 1,
      input_tokens: 50,
      cached_tokens: 5,
      output_tokens: 20,
      cost_usd: 2,
      cost_brl: 11,
    },
  ],
  time_series: [
    { timestamp: '2026-06-27T00:00:00Z', cost_usd: 10, cost_brl: 55 },
    { timestamp: '2026-06-28T00:00:00Z', cost_usd: 12.445455, cost_brl: 68.45 },
  ],
  history: {
    page: 1,
    per_page: 25,
    total_count: 2,
    rows: [
      {
        id: 2,
        created_at: '2026-06-28T11:00:00Z',
        resource: 'Assistente de respostas',
        account: { id: 85, name: 'Autonom.ia' },
        input_tokens: 100,
        cached_tokens: 20,
        output_tokens: 30,
        total_tokens: 130,
        cost_usd: 10,
        cost_brl: 55,
      },
    ],
  },
  ...overrides,
});

const mountPage = async (payload = makePayload()) => {
  CrmAiUsageAPI.get.mockResolvedValueOnce({ data: { payload } });
  const wrapper = mount(CrmAiUsagePage, {
    global: {
      stubs: {
        'fluent-icon': true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CrmAiUsagePage', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-28T12:00:00Z'));
    vi.clearAllMocks();
    CrmKanbanAPI.getReportAiVsHuman.mockResolvedValue({
      data: { payload: { ai_auto_moves: 0, ai_accepted: 0, ai_dismissed: 0 } },
    });
    Object.keys(emitterHandlers).forEach(key => {
      delete emitterHandlers[key];
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders cards and spend by resource with humanized labels', async () => {
    const wrapper = await mountPage();

    expect(wrapper.text()).toContain('AI Management');
    expect(wrapper.text()).toContain('live');
    expect(wrapper.text()).toContain('Weekly spend');
    expect(wrapper.text()).toContain('AI uses');
    expect(wrapper.text()).toContain('Automatic savings');
    expect(wrapper.text()).toContain('Average cost per use');
    expect(wrapper.text()).toContain('Assistente de respostas');
    expect(wrapper.text()).toContain('Base de conhecimento');
    expect(wrapper.text()).not.toContain('agente_resposta');
  });

  it('formats cost_brl as decimal money without treating it as cents', async () => {
    const wrapper = await mountPage();

    expect(wrapper.text()).toContain('R$123.45');
    expect(wrapper.text()).not.toContain('R$1.23');
  });

  it('applies ActionCable delta to cards, chart data and history without refetching', async () => {
    const wrapper = await mountPage();

    emitterHandlers[BUS_EVENTS.CRM_AI_USAGE_CREATED]({
      id: 3,
      account_id: 85,
      resource: 'Criação de e-mail',
      created_at: '2026-06-28T12:01:00Z',
      input_tokens: 70,
      cached_tokens: 10,
      output_tokens: 20,
      total_tokens: 90,
      cost_usd: 1,
    });
    await wrapper.vm.$nextTick();

    expect(CrmAiUsageAPI.get).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('Criação de e-mail');
    expect(wrapper.text()).toContain('R$128.95');
    expect(wrapper.text()).toContain('3');
    expect(wrapper.text()).toContain('90');
  });

  // #1969: sem financial_view o servidor manda só contagens; a tela mostra uso, nunca dinheiro.
  it('shows usage without money when the payload has no values', async () => {
    const wrapper = await mountPage({
      account: { id: 85, name: 'Autonom.ia' },
      period: makePayload().period,
      com_valores: false,
      totals: { usage_count: 2 },
      spend_by_resource: [
        { resource: 'Assistente de respostas', usage_count: 2 },
      ],
      time_series: [{ timestamp: '2026-06-28T00:00:00Z', usage_count: 2 }],
      history: {
        page: 1,
        per_page: 25,
        total_count: 1,
        rows: [
          {
            id: 2,
            created_at: '2026-06-28T11:00:00Z',
            resource: 'Assistente de respostas',
            account: { id: 85, name: 'Autonom.ia' },
            total_tokens: 130,
          },
        ],
      },
    });

    expect(wrapper.find('[data-sem-valores]').exists()).toBe(true);
    expect(wrapper.text()).toContain('AI uses');
    expect(wrapper.text()).toContain('Usage by feature');
    expect(wrapper.text()).toContain('Follow how much AI is used');
    expect(wrapper.text()).toContain('2 uses');
    expect(wrapper.text()).not.toContain('R$');
    expect(wrapper.text()).not.toContain('Weekly spend');

    emitterHandlers[BUS_EVENTS.CRM_AI_USAGE_CREATED]({
      id: 3,
      account_id: 85,
      resource: 'Assistente de respostas',
      created_at: '2026-06-28T12:01:00Z',
      total_tokens: 90,
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('3 uses');
    expect(wrapper.text()).not.toContain('R$');
  });

  it('refetches on period change with the selected group_by', async () => {
    const wrapper = await mountPage();
    CrmAiUsageAPI.get.mockResolvedValueOnce({
      data: { payload: makePayload({ time_series: [] }) },
    });

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Month')
      .trigger('click');
    await flushPromises();

    expect(CrmAiUsageAPI.get).toHaveBeenCalledTimes(2);
    expect(CrmAiUsageAPI.get).toHaveBeenLastCalledWith(
      expect.objectContaining({ group_by: 'day' })
    );
    expect(wrapper.text()).toContain('Monthly spend');
    expect(wrapper.text()).toContain('Monthly spend (by day)');
  });

  // #2000 — o "IA vs humano" saiu de Números e virou esta frase, sobre todos os funis que a pessoa vê.
  it('says in one sentence what the AI did in the stages, for all visible pipelines', async () => {
    CrmKanbanAPI.getReportAiVsHuman.mockResolvedValue({
      data: { payload: { ai_auto_moves: 3, ai_accepted: 2, ai_dismissed: 1 } },
    });
    const wrapper = await mountPage();

    expect(CrmKanbanAPI.getReportAiVsHuman).toHaveBeenCalledWith(
      expect.objectContaining({ todos_os_funis: true })
    );
    const bloco = wrapper.get('[data-ia-vs-humano]');
    expect(bloco.text()).toContain('What the AI did in the pipeline');
    expect(bloco.get('[data-ia-vs-humano-frase]').text()).toBe(
      'In this period, the AI moved customers to another stage on its own 3 times. It also suggested changes: the team accepted 2 and turned down 1.'
    );
  });

  it('says it moved no one on its own when the team only judged suggestions', async () => {
    CrmKanbanAPI.getReportAiVsHuman.mockResolvedValue({
      data: { payload: { ai_auto_moves: 0, ai_accepted: 1, ai_dismissed: 0 } },
    });
    const wrapper = await mountPage();

    expect(wrapper.get('[data-ia-vs-humano-frase]').text()).toBe(
      'In this period, the AI did not move anyone to another stage on its own. It also suggested changes: the team accepted 1 and turned down 0.'
    );
  });

  it('says plainly when the AI did nothing in the stages', async () => {
    const wrapper = await mountPage();

    expect(wrapper.get('[data-ia-vs-humano-frase]').text()).toBe(
      'In this period, the AI did not move anyone to another stage, nor suggest changes.'
    );
  });

  it('leaves the sentence out, and the rest of the page in, when the reading fails', async () => {
    CrmKanbanAPI.getReportAiVsHuman.mockRejectedValue(new Error('403'));
    const wrapper = await mountPage();

    expect(wrapper.find('[data-ia-vs-humano]').exists()).toBe(false);
    expect(wrapper.text()).toContain('AI uses');
  });

  it('reads the sentence again for the new period', async () => {
    const wrapper = await mountPage();
    CrmAiUsageAPI.get.mockResolvedValueOnce({
      data: { payload: makePayload() },
    });

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Month')
      .trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.getReportAiVsHuman).toHaveBeenCalledTimes(2);
  });
});
