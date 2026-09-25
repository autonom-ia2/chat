// Botões pela regra do servidor (#682): Enviar ao CRM só para quem pode criar
// card (Crm::CardPolicy#create?); Adicionar à campanha para quem gerencia a
// prospecção, e a escolha da campanha, dentro da janela, só com campaign_manage.
// O servidor diz as duas coisas no payload das configurações.
import { flushPromises } from '@vue/test-utils';
import CampaignsAPI from 'dashboard/api/campaigns';
import CampaignSelectionModal from '../components/campaign/CampaignSelectionModal.vue';
import BulkActionsBar from '../components/search/BulkActionsBar.vue';
import {
  buttonWithText,
  detailPanel,
  leadCard,
  mountSearchPage,
  settingsFixture,
} from './support/searchPageHarness';
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
vi.mock('dashboard/api/campaigns', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: [] }) },
}));

const SEND = 'PROSPECTING.SEARCH.SEND_TO_CRM';
const ADD = 'PROSPECTING.SEARCH.ADD_TO_CAMPAIGN';

// Onde cada botão aparece: barra de seleção, card do lead e painel lateral.
const visibleButtons = async (wrapper, text) => {
  const card = buttonWithText(leadCard(wrapper, 'Padaria Sol'), text);
  await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
  const bar = buttonWithText(wrapper.findComponent(BulkActionsBar), text);
  await buttonWithText(
    leadCard(wrapper, 'Padaria Sol'),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
  const panel = buttonWithText(detailPanel(wrapper), text);
  return { card: !!card, bar: !!bar, panel: !!panel };
};

const mountWith = (can_send_to_crm, can_manage_campaigns) =>
  mountSearchPage({
    settings: settingsFixture({ can_send_to_crm, can_manage_campaigns }),
  });

describe('ProspectingSearchPage · botões por permissão', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('sem permissão de criar card, Enviar ao CRM some da barra, do card e do painel', async () => {
    const wrapper = await mountWith(false, true);

    expect(await visibleButtons(wrapper, SEND)).toEqual({
      card: false,
      bar: false,
      panel: false,
    });
  });

  it('com permissão de criar card, Enviar ao CRM aparece nos três lugares', async () => {
    const wrapper = await mountWith(true, false);

    expect(await visibleButtons(wrapper, SEND)).toEqual({
      card: true,
      bar: true,
      panel: true,
    });
  });

  // O servidor só exige campaign_manage quando vem uma campanha
  // (authorize_campaign_update!): sem ela, o segmento sai só com a prospecção.
  // O botão segue essa regra; a escolha da campanha, dentro da janela, não.
  it('sem campaign_manage, Adicionar à campanha continua e a janela só cria o segmento, sem pedir as campanhas', async () => {
    const wrapper = await mountWith(true, false);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, ADD).trigger('click');
    await flushPromises();

    const modal = wrapper.findComponent(CampaignSelectionModal);
    expect(modal.props('canChooseCampaign')).toBe(false);
    expect(CampaignsAPI.get).not.toHaveBeenCalled();
    expect(buttonWithText(wrapper, SEND)).toBeTruthy();
  });

  it('com campaign_manage, a janela oferece também a escolha da campanha', async () => {
    const wrapper = await mountWith(false, true);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, ADD).trigger('click');
    await flushPromises();

    const modal = wrapper.findComponent(CampaignSelectionModal);
    expect(modal.props('canChooseCampaign')).toBe(true);
    expect(CampaignsAPI.get).toHaveBeenCalled();
    expect(buttonWithText(wrapper, SEND)).toBeUndefined();
  });

  it('quem só vê a prospecção não tem nenhum dos dois, mesmo com as permissões dos outros módulos', async () => {
    permission.canManage = false;
    const wrapper = await mountWith(true, true);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(buttonWithText(wrapper, SEND)).toBeUndefined();
    expect(buttonWithText(wrapper, ADD)).toBeUndefined();
  });
});
