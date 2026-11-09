// Botões pela regra do servidor (#682): Enviar ao CRM só para quem pode criar
// card (Crm::CardPolicy#create?), dito no payload das configurações.
// Adicionar à campanha por etiqueta saiu (#2695): a lista vira Público pelo
// "Guardar para mandar mensagem" da tela Achar empresas.
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

const mountWith = can_send_to_crm =>
  mountSearchPage({ settings: settingsFixture({ can_send_to_crm }) });

describe('ProspectingSearchPage · botões por permissão', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('sem permissão de criar card, Enviar ao CRM some da barra, do card e do painel', async () => {
    const wrapper = await mountWith(false);

    expect(await visibleButtons(wrapper, SEND)).toEqual({
      card: false,
      bar: false,
      panel: false,
    });
  });

  it('com permissão de criar card, Enviar ao CRM aparece nos três lugares', async () => {
    const wrapper = await mountWith(true);

    expect(await visibleButtons(wrapper, SEND)).toEqual({
      card: true,
      bar: true,
      panel: true,
    });
  });

  it('Adicionar à campanha não aparece mais na barra, no card nem no painel', async () => {
    const wrapper = await mountWith(true);

    expect(await visibleButtons(wrapper, ADD)).toEqual({
      card: false,
      bar: false,
      panel: false,
    });
  });

  it('quem só vê a prospecção não tem Enviar ao CRM, mesmo com a permissão do CRM', async () => {
    permission.canManage = false;
    const wrapper = await mountWith(true);

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(buttonWithText(wrapper, SEND)).toBeUndefined();
  });
});
