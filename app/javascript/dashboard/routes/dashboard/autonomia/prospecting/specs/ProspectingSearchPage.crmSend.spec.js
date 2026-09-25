// Enviar ao CRM pela tela de busca (#680): a barra de seleção, o card do lead e
// o painel lateral abrem a mesma janela de funil e estágio. O que o contador
// mostra é o que vai, mesmo com filtro (ACAO-X02). O resultado de cada lead
// troca o botão pelo link do card, e o histórico não some enquanto uma busca
// abre.
import { config, flushPromises } from '@vue/test-utils';
import FloatingVue from 'floating-vue';
import { createI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import {
  buttonWithText,
  deferred,
  detailPanel,
  historyCards,
  leadCard,
  leadNames,
  mountSearchPage,
  openResultFilters,
  choose,
} from './support/searchPageHarness';
import { leadCheckbox, linkWithText } from './support/resultsHelpers';
import { applyFilters } from './support/filtersHelpers';

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

// Só o contador ganha texto, para o número aparecer; o resto fica na chave.
config.global.plugins = [
  createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        PROSPECTING: { SEARCH: { SELECTED_COUNT: '{count} selecionados' } },
      },
    },
    missingWarn: false,
    fallbackWarn: false,
  }),
  FloatingVue,
];

const SEND = 'PROSPECTING.SEARCH.SEND_TO_CRM';

const sendModal = wrapper => wrapper.findComponent(CrmSendModal);
const modalLeadIds = wrapper =>
  sendModal(wrapper)
    .props('leads')
    .map(lead => lead.id);
const submitModal = async wrapper => {
  await sendModal(wrapper)
    .find('[data-test="crm-send-submit"]')
    .trigger('click');
  await flushPromises();
};
const openDetails = async (wrapper, name) => {
  await buttonWithText(
    leadCard(wrapper, name),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage · enviar ao CRM', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('a barra de seleção abre a janela com os selecionados e o destino da busca como sugestão', async () => {
    const wrapper = await mountSearchPage();

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await leadCheckbox(wrapper, 'Confeitaria Lua').trigger('change');
    expect(wrapper.text()).toContain('2 selecionados');
    expect(sendModal(wrapper).exists()).toBe(false);

    await buttonWithText(wrapper, SEND).trigger('click');
    await flushPromises();

    expect(modalLeadIds(wrapper)).toEqual([101, 103]);
    expect(sendModal(wrapper).props('suggestedPipelineId')).toBe(3);
    expect(sendModal(wrapper).props('suggestedStageId')).toBe(31);
    expect(AutonomiaProspectingAPI.createCrmCards).not.toHaveBeenCalled();
  });

  // #732: Pão Quente já está no CRM (card 555) e fica fora do envio em lote;
  // como não foi enviado, continua selecionado.
  it('manda os selecionados, troca o botão pelo link do card e tira da seleção só o que foi', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: {
        payload: {
          created: [
            { lead_id: 101, card_id: 1010, contact_id: 900, company_id: 5 },
          ],
          existing: [],
          failed: [
            { lead_id: 103, reason_code: 'invalid', message: 'Sem telefone' },
          ],
        },
      },
    });

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    await buttonWithText(wrapper, SEND).trigger('click');
    await flushPromises();
    await submitModal(wrapper);

    expect(AutonomiaProspectingAPI.createCrmCards).toHaveBeenCalledWith({
      leadIds: [101, 103],
      pipelineId: 3,
      stageId: 31,
    });
    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=1010');
    expect(
      buttonWithText(leadCard(wrapper, 'Confeitaria Lua'), SEND)
    ).toBeTruthy();
    expect(wrapper.text()).toContain('2 selecionados');
    expect(leadCheckbox(wrapper, 'Confeitaria Lua').element.checked).toBe(true);
    expect(useAlert).not.toHaveBeenCalled();
    expect(
      sendModal(wrapper).find('[data-test="crm-send-summary"]').exists()
    ).toBe(true);

    await sendModal(wrapper)
      .find('[data-test="crm-send-close"]')
      .trigger('click');
    expect(sendModal(wrapper).exists()).toBe(false);
  });

  it('o card do lead abre a janela só com ele', async () => {
    const wrapper = await mountSearchPage();

    await buttonWithText(leadCard(wrapper, 'Confeitaria Lua'), SEND).trigger(
      'click'
    );
    await flushPromises();

    expect(modalLeadIds(wrapper)).toEqual([103]);
  });

  it('o painel do lead abre a janela por cima dele', async () => {
    const wrapper = await mountSearchPage();

    await openDetails(wrapper, 'Padaria Sol');
    await buttonWithText(detailPanel(wrapper), SEND).trigger('click');
    await flushPromises();

    expect(modalLeadIds(wrapper)).toEqual([101]);
    expect(detailPanel(wrapper).exists()).toBe(true);
  });

  it('lead com card mostra o link, sem botão de enviar', async () => {
    const wrapper = await mountSearchPage();
    const card = leadCard(wrapper, 'Pão Quente');

    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.OPEN_CRM_CARD').attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=555');
    expect(buttonWithText(card, SEND)).toBeUndefined();
  });

  it('quem só vê não tem enviar ao CRM em lugar nenhum', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage();

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    expect(buttonWithText(wrapper, SEND)).toBeUndefined();

    await openDetails(wrapper, 'Padaria Sol');
    expect(buttonWithText(detailPanel(wrapper), SEND)).toBeUndefined();
  });

  it('com filtro, o contador é o que vai: o que o filtro esconde sai da seleção', async () => {
    const wrapper = await mountSearchPage();

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    expect(wrapper.text()).toContain('3 selecionados');

    await openResultFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'yes');
    await applyFilters(wrapper);
    expect(leadNames(wrapper)).toEqual(['Padaria Sol', 'Confeitaria Lua']);
    expect(wrapper.text()).toContain('2 selecionados');

    await buttonWithText(wrapper, SEND).trigger('click');
    await flushPromises();
    expect(modalLeadIds(wrapper)).toEqual([101, 103]);
  });
});

describe('ProspectingSearchPage · histórico enquanto a busca abre', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('continua listando as buscas enquanto outra busca carrega', async () => {
    const wrapper = await mountSearchPage();
    const pending = deferred();
    AutonomiaProspectingAPI.getSearch.mockReturnValueOnce(pending.promise);

    await historyCards(wrapper)[1].find('button').trigger('click');
    await flushPromises();

    expect(historyCards(wrapper)).toHaveLength(2);
    expect(historyCards(wrapper)[1].classes()).toContain('border-n-brand');

    pending.resolve({ data: { payload: { search: { id: 12 }, leads: [] } } });
    await flushPromises();
    expect(historyCards(wrapper)).toHaveLength(2);
  });
});
