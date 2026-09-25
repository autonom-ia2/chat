// Decisor dos leads na tela de listas (#679). A lista mostra o mesmo decisor da
// busca: o da pesquisa. O nome gravado antes dela (palpite da IA da E2, ou o
// sócio de um CNPJ de uma pesquisa anterior) continua no lead, mas não aparece
// como decisor quando a pesquisa terminou sem dono.
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ProspectingListsPage from '../pages/ProspectingListsPage.vue';
import { ChoiceSelectStub, moonLead } from './support/searchPageHarness';
import { researchBlock } from './support/researchFixtures';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getLists: vi.fn(),
    getLeads: vi.fn(),
    getList: vi.fn(),
    verifyLeadWhatsApp: vi.fn(),
  },
}));
vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const LIST = { id: 7, name: 'Padarias', leads_count: 1, lead_ids: [103] };

const mountWith = async lead => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: { research_enabled: true } },
  });
  AutonomiaProspectingAPI.getLists.mockResolvedValue({
    data: { payload: [LIST] },
  });
  AutonomiaProspectingAPI.getLeads.mockResolvedValue({
    data: { payload: [lead] },
  });
  AutonomiaProspectingAPI.getList.mockResolvedValue({
    data: { payload: { ...LIST, leads: [lead] } },
  });
  AutonomiaProspectingAPI.verifyLeadWhatsApp.mockResolvedValue({
    data: { payload: {} },
  });
  CampaignsAPI.get.mockResolvedValue({ data: [] });
  CrmKanbanAPI.getPipelines.mockResolvedValue({ data: { payload: [] } });
  CrmKanbanAPI.getStages.mockResolvedValue({ data: { payload: [] } });

  const wrapper = mount(ProspectingListsPage, {
    global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
  });
  await flushPromises();
  return wrapper;
};

describe('ProspectingListsPage: decisor da pesquisa', () => {
  it('pesquisa sem dono: o nome antigo não aparece como decisor', async () => {
    const wrapper = await mountWith(
      moonLead({
        decision_name: 'Joao Palpite IA',
        decision_role: 'Gerente',
        research: researchBlock({
          decision_status: 'no_result',
          no_decision_reason: 'only_companies',
          owners: [],
          decision: null,
        }),
      })
    );

    expect(wrapper.text()).not.toContain('Joao Palpite IA');
    expect(wrapper.find('[data-test="lead-legacy-decision"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-test="lead-research-decision"]').text()
    ).toContain('PROSPECTING.RESEARCH.DECISION_LINE.NOT_CONFIRMED');
  });

  it('pesquisa com dono: o decisor vem da pesquisa, não do nome antigo', async () => {
    const wrapper = await mountWith(
      moonLead({ decision_name: 'Joao Palpite IA', research: researchBlock() })
    );

    expect(wrapper.text()).not.toContain('Joao Palpite IA');
    expect(
      wrapper.find('[data-test="lead-research-decision"]').text()
    ).toContain('JOAO DA SILVA');
  });

  it('lead sem bloco research mostra o decisor gravado', async () => {
    const wrapper = await mountWith(moonLead());

    expect(wrapper.find('[data-test="lead-legacy-decision"]').text()).toContain(
      'Ana'
    );
  });
});
