// Botões pela permissão do módulo que eles alteram (#682): Enviar ao CRM só
// para quem pode criar card (Crm::CardPolicy#create?) e Adicionar à campanha
// só para quem tem campaign_manage. O servidor diz as duas coisas no payload
// das configurações; a permissão de prospecção continua valendo por cima.
import { flushPromises } from '@vue/test-utils';
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

  it('sem campaign_manage, Adicionar à campanha some da barra de seleção', async () => {
    const wrapper = await mountWith(true, false);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(buttonWithText(wrapper, ADD)).toBeUndefined();
    expect(buttonWithText(wrapper, SEND)).toBeTruthy();
  });

  it('com campaign_manage, Adicionar à campanha aparece', async () => {
    const wrapper = await mountWith(false, true);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(buttonWithText(wrapper, ADD)).toBeTruthy();
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
