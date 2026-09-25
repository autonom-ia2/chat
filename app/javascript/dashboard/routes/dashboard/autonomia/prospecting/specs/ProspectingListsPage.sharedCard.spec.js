// A tela de Listas usa o mesmo card e o mesmo painel da busca (#682, frente B):
// LeadCard e LeadDetailDrawer, sem cópia do markup. As ações próprias das
// Listas continuam: remover o lead da lista e montar o segmento de campanha.
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import LeadCard from '../components/search/LeadCard.vue';
import LeadDetailDrawer from '../components/search/LeadDetailDrawer.vue';
import ProspectingListsPage from '../pages/ProspectingListsPage.vue';
import {
  ChoiceSelectStub,
  PIPELINES,
  STAGES_BY_PIPELINE,
  buttonWithText,
  detailPanel,
  hotBreadLead,
  moonLead,
  sunLead,
} from './support/searchPageHarness';

const permission = vi.hoisted(() => ({ canManage: true }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => permission.canManage) };
});
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getLists: vi.fn(),
    getLeads: vi.fn(),
    getList: vi.fn(),
    verifyLeadWhatsApp: vi.fn(),
    removeLeadFromList: vi.fn(),
    researchLead: vi.fn(),
    enrichLead: vi.fn(),
    createCrmCards: vi.fn(),
  },
}));
vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const LIST = { id: 7, name: 'Padarias', leads_count: 3 };
const OPEN_DETAILS = 'PROSPECTING.SEARCH.OPEN_DETAILS';
const REMOVE = 'PROSPECTING.LISTS.REMOVE_LEAD';

const listPayload = leads => ({
  ...LIST,
  leads_count: leads.length,
  lead_ids: leads.map(lead => lead.id),
  leads,
});

const mountLists = async (leads = [sunLead(), hotBreadLead(), moonLead()]) => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: {
      payload: {
        research_enabled: true,
        default_crm_pipeline_id: 3,
        default_crm_stage_id: 31,
        can_send_to_crm: true,
      },
    },
  });
  AutonomiaProspectingAPI.getLists.mockResolvedValue({
    data: { payload: [LIST] },
  });
  AutonomiaProspectingAPI.getLeads.mockResolvedValue({
    data: { payload: leads },
  });
  AutonomiaProspectingAPI.getList.mockResolvedValue({
    data: { payload: listPayload(leads) },
  });
  AutonomiaProspectingAPI.verifyLeadWhatsApp.mockResolvedValue({
    data: { payload: {} },
  });
  CampaignsAPI.get.mockResolvedValue({ data: [] });
  CrmKanbanAPI.getPipelines.mockResolvedValue({ data: { payload: PIPELINES } });
  CrmKanbanAPI.getStages.mockImplementation(pipelineId =>
    Promise.resolve({ data: { payload: STAGES_BY_PIPELINE[pipelineId] } })
  );

  const wrapper = mount(ProspectingListsPage, {
    global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
  });
  await flushPromises();
  return wrapper;
};

const cardOf = (wrapper, name) =>
  wrapper
    .findAllComponents(LeadCard)
    .find(card => card.props('lead').name === name);

describe('ProspectingListsPage · mesmo card e painel da busca', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('cada lead da lista é um LeadCard, o mesmo da busca, sem caixa de seleção', async () => {
    const wrapper = await mountLists();

    const cards = wrapper.findAllComponents(LeadCard);
    expect(cards.map(card => card.props('lead').id)).toEqual([101, 102, 103]);
    cards.forEach(card => {
      expect(card.find('input[type="checkbox"]').exists()).toBe(false);
    });
    expect(
      cardOf(wrapper, 'Padaria Sol').find('[data-test="lead-phone"]').exists()
    ).toBe(true);
  });

  it('Abrir detalhes abre o LeadDetailDrawer da busca com o lead do card', async () => {
    const wrapper = await mountLists();
    expect(wrapper.findComponent(LeadDetailDrawer).exists()).toBe(false);

    await buttonWithText(cardOf(wrapper, 'Pão Quente'), OPEN_DETAILS).trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.findComponent(LeadDetailDrawer).exists()).toBe(true);
    expect(detailPanel(wrapper).find('h2').text()).toBe('Pão Quente');
    expect(detailPanel(wrapper).text()).toContain('Fechado aos domingos');

    await detailPanel(wrapper)
      .find('button[title="PROSPECTING.SEARCH.CLOSE_DETAILS"]')
      .trigger('click');
    expect(wrapper.findComponent(LeadDetailDrawer).exists()).toBe(false);
  });

  it('clicar no corpo do card também abre o painel, como na busca', async () => {
    const wrapper = await mountLists();

    await cardOf(wrapper, 'Confeitaria Lua').find('h3').trigger('click');
    await flushPromises();

    expect(detailPanel(wrapper).find('h2').text()).toBe('Confeitaria Lua');
  });

  it('Enviar ao CRM do painel abre a mesma janela só com o lead aberto', async () => {
    const wrapper = await mountLists();

    await buttonWithText(cardOf(wrapper, 'Padaria Sol'), OPEN_DETAILS).trigger(
      'click'
    );
    await flushPromises();
    await buttonWithText(
      detailPanel(wrapper),
      'PROSPECTING.SEARCH.SEND_TO_CRM'
    ).trigger('click');
    await flushPromises();

    const modal = wrapper.findComponent(CrmSendModal);
    expect(modal.props('leads').map(lead => lead.id)).toEqual([101]);
  });

  it('o painel mostra o estágio padrão do CRM da conta', async () => {
    const wrapper = await mountLists();

    await buttonWithText(cardOf(wrapper, 'Padaria Sol'), OPEN_DETAILS).trigger(
      'click'
    );
    await flushPromises();

    expect(detailPanel(wrapper).text()).toContain('Novo');
  });

  it('remover da lista continua no card e tira o lead da lista', async () => {
    const wrapper = await mountLists();
    AutonomiaProspectingAPI.removeLeadFromList.mockResolvedValue({
      data: { payload: listPayload([sunLead(), moonLead()]) },
    });

    await buttonWithText(cardOf(wrapper, 'Pão Quente'), REMOVE).trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.removeLeadFromList).toHaveBeenCalledWith(
      7,
      102
    );
    expect(
      wrapper.findAllComponents(LeadCard).map(card => card.props('lead').id)
    ).toEqual([101, 103]);
  });

  it('remover não abre o painel do lead', async () => {
    const wrapper = await mountLists();
    AutonomiaProspectingAPI.removeLeadFromList.mockResolvedValue({
      data: { payload: listPayload([sunLead(), moonLead()]) },
    });

    await buttonWithText(cardOf(wrapper, 'Pão Quente'), REMOVE).trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.findComponent(LeadDetailDrawer).exists()).toBe(false);
  });

  it('campanha continua na lista e abre o segmento de campanha', async () => {
    const wrapper = await mountLists();

    await buttonWithText(
      wrapper,
      'PROSPECTING.LISTS.CAMPAIGN_SEGMENT_TITLE'
    ).trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain(
      'PROSPECTING.LISTS.CAMPAIGN_SEGMENT_CREATE'
    );
  });

  it('quem só vê não tem remover nem campanha, mas abre o painel', async () => {
    permission.canManage = false;
    const wrapper = await mountLists();

    expect(buttonWithText(wrapper, REMOVE)).toBeUndefined();
    expect(
      buttonWithText(wrapper, 'PROSPECTING.LISTS.CAMPAIGN_SEGMENT_TITLE')
    ).toBeUndefined();
    expect(AutonomiaProspectingAPI.verifyLeadWhatsApp).not.toHaveBeenCalled();

    await buttonWithText(cardOf(wrapper, 'Padaria Sol'), OPEN_DETAILS).trigger(
      'click'
    );
    await flushPromises();
    expect(detailPanel(wrapper).find('h2').text()).toBe('Padaria Sol');
  });

  it('o markup do card não é mais copiado na página de Listas', async () => {
    const wrapper = await mountLists();

    const listLeadArticles = wrapper
      .findAll('article')
      .filter(article => article.text().includes(OPEN_DETAILS));
    expect(listLeadArticles).toHaveLength(3);
    expect(wrapper.findAllComponents(LeadCard)).toHaveLength(3);
  });
});
