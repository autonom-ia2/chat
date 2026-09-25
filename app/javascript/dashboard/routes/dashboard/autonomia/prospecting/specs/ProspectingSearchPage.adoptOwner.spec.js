// Usar como contato pelo painel do lead (#680): um sócio de Quem atende vira o
// decisor e o contato do lead. A resposta é o lead inteiro, que troca o da
// tela.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import {
  bakerySearch,
  buttonWithText,
  deferred,
  detailPanel,
  leadCard,
  mountSearchPage,
  sunLead,
} from './support/searchPageHarness';
import { researchBlock } from './support/researchFixtures';
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
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const USE = 'PROSPECTING.RESEARCH.PANEL.USE_AS_CONTACT';
const CURRENT = 'PROSPECTING.RESEARCH.PANEL.CURRENT_CONTACT';

const researchedLead = (extra = {}) =>
  sunLead({ research: researchBlock(), contact_id: 900, ...extra });

const mountWithResearch = async () => {
  const search = bakerySearch();
  const wrapper = await mountSearchPage({
    searches: [search],
    payloads: { 11: { search, leads: [researchedLead()] } },
  });
  await buttonWithText(
    leadCard(wrapper, 'Padaria Sol'),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
  return wrapper;
};

const ownerItems = wrapper =>
  detailPanel(wrapper).findAll('[data-test="research-owners"] li');

describe('ProspectingSearchPage · usar sócio como contato', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('adota o sócio, troca o lead pelo da resposta e avisa', async () => {
    const wrapper = await mountWithResearch();
    AutonomiaProspectingAPI.adoptOwner.mockResolvedValue({
      data: {
        payload: researchedLead({
          contact_id: 901,
          decision_name: 'MARIA DA SILVA',
          research: researchBlock({
            decision: { name: 'MARIA DA SILVA', role: 'SOCIO' },
          }),
        }),
      },
    });

    await buttonWithText(ownerItems(wrapper)[1], USE).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.adoptOwner).toHaveBeenCalledWith(
      101,
      'MARIA DA SILVA'
    );
    expect(ownerItems(wrapper)[1].text()).toContain(CURRENT);
    expect(buttonWithText(ownerItems(wrapper)[0], USE)).toBeTruthy();
    expect(
      linkWithText(
        detailPanel(wrapper),
        'PROSPECTING.SEARCH.OPEN_CONTACT'
      ).attributes('href')
    ).toBe('/app/accounts/1/contacts/901');
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.RESEARCH.PANEL.OWNER_ADOPTED'
    );
  });

  it('enquanto salva, os botões dos sócios ficam parados', async () => {
    const wrapper = await mountWithResearch();
    const pending = deferred();
    AutonomiaProspectingAPI.adoptOwner.mockReturnValue(pending.promise);

    await buttonWithText(ownerItems(wrapper)[1], USE).trigger('click');
    await flushPromises();

    const saving = buttonWithText(
      ownerItems(wrapper)[1],
      'PROSPECTING.RESEARCH.PANEL.ADOPTING'
    );
    expect(saving.element.disabled).toBe(true);

    pending.reject({ response: { data: { error: 'Sócio fora da lista' } } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Sócio fora da lista');
    expect(ownerItems(wrapper)[0].text()).toContain(CURRENT);
    expect(buttonWithText(ownerItems(wrapper)[1], USE).element.disabled).toBe(
      false
    );
  });
});
