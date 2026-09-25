// Enviar ao CRM pela tela de Listas (#680, ACAO-X01): cada lead e a lista
// inteira abrem a mesma janela de funil e estágio da busca, com o destino
// padrão da conta como sugestão. O que foi ganha o link do card.
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import ProspectingListsPage from '../pages/ProspectingListsPage.vue';
import {
  ChoiceSelectStub,
  PIPELINES,
  STAGES_BY_PIPELINE,
  buttonWithText,
  hotBreadLead,
  moonLead,
  sunLead,
} from './support/searchPageHarness';
import { linkWithText } from './support/resultsHelpers';

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
    createCrmCards: vi.fn(),
  },
}));
vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const SEND = 'PROSPECTING.SEARCH.SEND_TO_CRM';
const SEND_LIST = 'PROSPECTING.LISTS.SEND_LIST_TO_CRM';
const LIST = { id: 7, name: 'Padarias', leads_count: 3 };

const mountLists = async (
  leads = [sunLead(), hotBreadLead(), moonLead()],
  { canSendToCrm = true } = {}
) => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: {
      payload: {
        default_crm_pipeline_id: 3,
        default_crm_stage_id: 31,
        can_send_to_crm: canSendToCrm,
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
    data: {
      payload: { ...LIST, lead_ids: leads.map(lead => lead.id), leads },
    },
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

const leadRow = (wrapper, name) =>
  wrapper
    .findAll('article')
    .find(article => article.find('h3').text() === name);
const sendModal = wrapper => wrapper.findComponent(CrmSendModal);

describe('ProspectingListsPage · enviar ao CRM', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('o botão do lead abre a janela só com ele e o destino padrão como sugestão', async () => {
    const wrapper = await mountLists();

    await buttonWithText(leadRow(wrapper, 'Padaria Sol'), SEND).trigger(
      'click'
    );
    await flushPromises();

    expect(
      sendModal(wrapper)
        .props('leads')
        .map(lead => lead.id)
    ).toEqual([101]);
    expect(sendModal(wrapper).props('suggestedPipelineId')).toBe(3);
    expect(sendModal(wrapper).props('suggestedStageId')).toBe(31);
  });

  it('enviar a lista manda todos os leads dela e troca o botão pelo link do card', async () => {
    const wrapper = await mountLists();
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: {
        payload: {
          created: [
            { lead_id: 101, card_id: 1010, contact_id: 900 },
            { lead_id: 103, card_id: 1030, contact_id: 930 },
          ],
          existing: [{ lead_id: 102, card_id: 555 }],
          failed: [],
        },
      },
    });

    await buttonWithText(wrapper, SEND_LIST).trigger('click');
    await flushPromises();
    await sendModal(wrapper)
      .find('[data-test="crm-send-submit"]')
      .trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createCrmCards).toHaveBeenCalledWith({
      leadIds: [101, 102, 103],
      pipelineId: 3,
      stageId: 31,
    });
    const lua = leadRow(wrapper, 'Confeitaria Lua');
    expect(
      linkWithText(lua, 'PROSPECTING.SEARCH.OPEN_CRM_CARD').attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=1030');
    expect(
      linkWithText(lua, 'PROSPECTING.SEARCH.OPEN_CONTACT').attributes('href')
    ).toBe('/app/accounts/1/contacts/930');
    expect(buttonWithText(lua, SEND)).toBeUndefined();

    await sendModal(wrapper)
      .find('[data-test="crm-send-close"]')
      .trigger('click');
    expect(sendModal(wrapper).exists()).toBe(false);
  });

  // #682: a permissão de criar card do CRM (Crm::CardPolicy#create?) vem do
  // servidor; sem ela, nem o lead nem a lista têm o botão.
  it('sem permissão de criar card, a lista e o lead ficam sem enviar ao CRM', async () => {
    const wrapper = await mountLists(undefined, { canSendToCrm: false });

    expect(buttonWithText(wrapper, SEND_LIST)).toBeUndefined();
    expect(
      buttonWithText(leadRow(wrapper, 'Padaria Sol'), SEND)
    ).toBeUndefined();
  });

  it('com permissão de criar card, a lista e o lead têm enviar ao CRM', async () => {
    const wrapper = await mountLists();

    expect(buttonWithText(wrapper, SEND_LIST)).toBeTruthy();
    expect(buttonWithText(leadRow(wrapper, 'Padaria Sol'), SEND)).toBeTruthy();
  });

  it('quem só vê não tem enviar ao CRM', async () => {
    permission.canManage = false;
    const wrapper = await mountLists();

    expect(buttonWithText(wrapper, SEND_LIST)).toBeUndefined();
    expect(
      buttonWithText(leadRow(wrapper, 'Padaria Sol'), SEND)
    ).toBeUndefined();
  });
});
