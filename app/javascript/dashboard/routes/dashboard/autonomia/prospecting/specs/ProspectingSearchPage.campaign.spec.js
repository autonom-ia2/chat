// Adicionar à campanha a partir da seleção da busca (#680, ACAO-25): a barra
// de seleção abre a janela com os leads selecionados e o termo da busca como
// nome do segmento.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import CampaignSelectionModal from '../components/campaign/CampaignSelectionModal.vue';
import { buttonWithText, mountSearchPage } from './support/searchPageHarness';
import { leadCheckbox } from './support/resultsHelpers';

const permission = vi.hoisted(() => ({ canManage: true }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => permission.canManage) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);
vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));

const ADD = 'PROSPECTING.SEARCH.ADD_TO_CAMPAIGN';
const campaignModal = wrapper => wrapper.findComponent(CampaignSelectionModal);

describe('ProspectingSearchPage · adicionar à campanha', () => {
  beforeEach(() => {
    permission.canManage = true;
    CampaignsAPI.get.mockResolvedValue({ data: [] });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('abre com os selecionados e o termo da busca como nome do segmento', async () => {
    const wrapper = await mountSearchPage();

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await leadCheckbox(wrapper, 'Confeitaria Lua').trigger('change');
    await buttonWithText(wrapper, ADD).trigger('click');
    await flushPromises();

    expect(
      campaignModal(wrapper)
        .props('leads')
        .map(lead => lead.id)
    ).toEqual([101, 103]);
    expect(campaignModal(wrapper).props('defaultSegmentName')).toBe('padaria');
  });

  it('manda os selecionados e fecha pelo botão da janela', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockResolvedValue({
      data: {
        payload: {
          segment: {
            label: { id: 5, title: 'prospeccao_70_padaria' },
            campaign: null,
            eligible_count: 1,
            blocked_count: 0,
            created_contacts_count: 0,
            blocked_leads: [],
          },
        },
      },
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, ADD).trigger('click');
    await flushPromises();
    await campaignModal(wrapper)
      .find('[data-test="campaign-submit"]')
      .trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.addLeadsToCampaign).toHaveBeenCalledWith({
      leadIds: [101],
      campaignId: '',
      segmentName: 'padaria',
    });
    await campaignModal(wrapper)
      .find('[data-test="campaign-close"]')
      .trigger('click');
    expect(campaignModal(wrapper).exists()).toBe(false);
  });

  it('quem só vê não tem adicionar à campanha', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage();

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(buttonWithText(wrapper, ADD)).toBeUndefined();
  });
});
