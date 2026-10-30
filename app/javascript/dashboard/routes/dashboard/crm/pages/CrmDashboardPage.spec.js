import { flushPromises, mount } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { withFullI18n } from 'test-i18n';
import CrmDashboardPage from './CrmDashboardPage.vue';

// #2075 — quem vê os valores de venda (o padrão das telas sem função personalizada).
vi.mock('../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canSeeSalesValues: { value: true } }),
}));

// #2000 — o bloco "IA vs humano" saiu do painel de Números (virou uma frase na Gestão de IA): a página
// não lê mais o relatório e não mostra o bloco; o resto (retornos) fica.
withFullI18n();

const payload = data => Promise.resolve({ data: { payload: data } });

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getReportPipelines: vi.fn(),
    getReportSummary: vi.fn(),
    getReportFunnel: vi.fn(),
    getReportAiVsHuman: vi.fn(),
    getReportThroughput: vi.fn(),
    getReportFollowUps: vi.fn(),
    getReportWorkload: vi.fn(),
    getReportMeetings: vi.fn(),
  },
}));
vi.mock('dashboard/api/ctwaCampaigns', () => ({
  default: {
    get: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
  },
}));
vi.mock('dashboard/api/metaConversions', () => ({
  default: { getSummary: vi.fn() },
}));
vi.mock('dashboard/components-next/sidebar/fork/useMenuNovo', () => ({
  useMenuNovo: () => ({ ligado: { value: false } }),
}));
vi.mock('shared/components/charts/BarChart.vue', () => ({
  default: { name: 'BarChart', template: '<div />' },
}));

describe('CrmDashboardPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmKanbanAPI.getReportPipelines.mockReturnValue(
      payload([{ id: 1, name: 'Vendas', is_default: true }])
    );
    CrmKanbanAPI.getReportSummary.mockReturnValue(payload({}));
    CrmKanbanAPI.getReportFunnel.mockReturnValue(payload({ stages: [] }));
    CrmKanbanAPI.getReportThroughput.mockReturnValue(payload({ series: [] }));
    CrmKanbanAPI.getReportFollowUps.mockReturnValue(
      payload({ by_status: { pending: 2 }, overdue: 0, due_soon: 1 })
    );
    CrmKanbanAPI.getReportWorkload.mockReturnValue(
      payload({ responsibles: [] })
    );
  });

  it('no longer reads nor shows the "AI vs human" block', async () => {
    const wrapper = mount(CrmDashboardPage, {
      global: { stubs: { CrmVistasNumeros: true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(CrmKanbanAPI.getReportSummary).toHaveBeenCalled();
    expect(CrmKanbanAPI.getReportAiVsHuman).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('AI vs human');
    expect(wrapper.text()).toContain('Follow-ups');
  });
});
