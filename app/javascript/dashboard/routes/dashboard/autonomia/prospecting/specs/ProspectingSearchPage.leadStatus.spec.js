// Lead já no CRM, descartar e criar contatos (#732, itens 1 e 10). O card e o
// painel dizem funil, estágio e responsável do card que o lead já tem; o envio
// em lote ao CRM deixa de fora quem já está lá ou foi descartado; descartar
// pede motivo e deixa o lead visível, marcado; criar contatos em lote usa o
// contato do lead avulso.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import DiscardLeadsModal from '../components/search/DiscardLeadsModal.vue';
import {
  bakerySearch,
  buttonWithText,
  choose,
  confirmation,
  detailPanel,
  hotBreadLead,
  leadCard,
  moonLead,
  mountSearchPage,
  sunLead,
} from './support/searchPageHarness';
import { leadCheckbox, linkWithText } from './support/resultsHelpers';

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

const IN_CRM = 'PROSPECTING.LEAD_STATUS.IN_CRM';
const DISCARDED = 'PROSPECTING.LEAD_STATUS.DISCARDED';
const REFUSE_ACTION = 'PROSPECTING.CONSENT_REFUSAL.REFUSE.ACTION';
const WITHDRAW_ACTION = 'PROSPECTING.CONSENT_REFUSAL.WITHDRAW.ACTION';
const REFUSED_AT = '2026-09-26T12:00:00Z';
const presence = {
  card_id: 555,
  pipeline_name: 'Vendas',
  stage_name: 'Novo',
  owner_name: 'Ana Souza',
};

// Sol fora do CRM, Pão Quente no CRM, Lua descartada.
const mountWithStatuses = () =>
  mountSearchPage({
    payloads: {
      11: {
        search: bakerySearch(),
        leads: [
          sunLead(),
          hotBreadLead({ crm_presence: presence }),
          moonLead({ status: 'discarded', discard_reason: 'Sem interesse' }),
        ],
      },
    },
  });

const statusBanner = card => card.find('[data-test="lead-status"]');
const refusedBadge = scope => scope.find('[data-test="lead-consent-refused"]');

const openDetails = async (wrapper, name) => {
  await buttonWithText(
    leadCard(wrapper, name),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
};

const selectAll = async wrapper => {
  await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
    'click'
  );
};

describe('ProspectingSearchPage · lead no CRM, descarte e contatos', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('o card do lead no CRM diz funil, estágio e responsável; os outros não', async () => {
    const wrapper = await mountWithStatuses();

    const hot = statusBanner(leadCard(wrapper, 'Pão Quente'));
    expect(hot.text()).toContain(IN_CRM);
    expect(hot.text()).toContain('Vendas, Novo, Ana Souza');
    expect(statusBanner(leadCard(wrapper, 'Padaria Sol')).exists()).toBe(false);
  });

  it('o card do lead descartado diz o motivo e não oferece Enviar ao CRM', async () => {
    const wrapper = await mountWithStatuses();
    const moon = leadCard(wrapper, 'Confeitaria Lua');

    expect(statusBanner(moon).text()).toContain(DISCARDED);
    expect(statusBanner(moon).text()).toContain('Sem interesse');
    expect(
      buttonWithText(moon, 'PROSPECTING.SEARCH.SEND_TO_CRM')
    ).toBeUndefined();
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.SEND_TO_CRM'
      )
    ).toBeTruthy();
  });

  it('o envio em lote ao CRM leva só quem não está no CRM nem foi descartado', async () => {
    const wrapper = await mountWithStatuses();

    await selectAll(wrapper);
    expect(wrapper.text()).toContain('PROSPECTING.BULK.CRM_EXCLUDED');
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SEND_TO_CRM').trigger(
      'click'
    );
    await flushPromises();

    const modal = wrapper.findComponent(CrmSendModal);
    expect(modal.props('leads').map(lead => lead.id)).toEqual([101]);
  });

  it('com só leads no CRM ou descartados selecionados, Enviar ao CRM fica desligado', async () => {
    const wrapper = await mountWithStatuses();

    await leadCheckbox(wrapper, 'Pão Quente').trigger('change');
    await leadCheckbox(wrapper, 'Confeitaria Lua').trigger('change');

    const send = buttonWithText(wrapper, 'PROSPECTING.SEARCH.SEND_TO_CRM');
    expect(send.attributes('disabled')).toBeDefined();
  });

  it('descarta a seleção com motivo: o lead fica na busca, marcado, e sai da seleção', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.discardLeads.mockResolvedValue({
      data: {
        payload: {
          leads: [
            sunLead({
              status: 'discarded',
              discard_reason: 'PROSPECTING.DISCARD.REASONS.NO_INTEREST',
            }),
          ],
          missing_lead_ids: [],
        },
      },
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, 'PROSPECTING.DISCARD.ACTION').trigger(
      'click'
    );
    expect(wrapper.findComponent(DiscardLeadsModal).exists()).toBe(true);
    await choose(wrapper, 'PROSPECTING.DISCARD.REASON', 'NO_INTEREST');
    await wrapper.find('[data-test="discard-submit"]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.discardLeads).toHaveBeenCalledWith({
      leadIds: [101],
      reason: 'PROSPECTING.DISCARD.REASONS.NO_INTEREST',
    });
    const sol = leadCard(wrapper, 'Padaria Sol');
    expect(statusBanner(sol).text()).toContain(DISCARDED);
    expect(leadCheckbox(wrapper, 'Padaria Sol').element.checked).toBe(false);
    expect(wrapper.findComponent(DiscardLeadsModal).exists()).toBe(false);
  });

  it('cria contatos em lote para os não descartados e resume o resultado', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.createLeadContacts.mockResolvedValue({
      data: {
        payload: {
          created: [{ lead_id: 102, contact_id: 901 }],
          existing: [{ lead_id: 101, contact_id: 900 }],
          failed: [],
        },
      },
    });

    await selectAll(wrapper);
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CONTACTS').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadContacts).toHaveBeenCalledWith([
      101, 102,
    ]);
    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.BULK.CONTACTS_RESULT');
    expect(
      linkWithText(
        leadCard(wrapper, 'Pão Quente'),
        'PROSPECTING.SEARCH.OPEN_CONTACT'
      ).attributes('href')
    ).toBe('/app/accounts/1/contacts/901');
  });

  it('o painel mostra o lead no CRM e descarta um lead só', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.discardLeads.mockResolvedValue({
      data: { payload: { leads: [], missing_lead_ids: [] } },
    });

    await openDetails(wrapper, 'Pão Quente');
    const panel = detailPanel(wrapper);
    expect(statusBanner(panel).text()).toContain('Vendas, Novo, Ana Souza');

    await buttonWithText(panel, 'PROSPECTING.DISCARD.ACTION').trigger('click');
    await choose(wrapper, 'PROSPECTING.DISCARD.REASON', 'CLOSED');
    await wrapper.find('[data-test="discard-submit"]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.discardLeads).toHaveBeenCalledWith({
      leadIds: [102],
      reason: 'PROSPECTING.DISCARD.REASONS.CLOSED',
    });
  });

  it('o painel do lead descartado desfaz o descarte', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.updateLead.mockResolvedValue({
      data: { payload: moonLead({ status: 'new_lead', discard_reason: null }) },
    });

    await openDetails(wrapper, 'Confeitaria Lua');
    const panel = detailPanel(wrapper);
    expect(buttonWithText(panel, 'PROSPECTING.DISCARD.ACTION')).toBeUndefined();
    await buttonWithText(panel, 'PROSPECTING.LEAD_STATUS.RESTORE').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.updateLead).toHaveBeenCalledWith(103, {
      status: 'new_lead',
    });
    expect(statusBanner(leadCard(wrapper, 'Confeitaria Lua')).exists()).toBe(
      false
    );
  });

  it('sem prospecting_manage não há descartar nem criar contatos', async () => {
    permission.canManage = false;
    const wrapper = await mountWithStatuses();

    await selectAll(wrapper);
    expect(
      buttonWithText(wrapper, 'PROSPECTING.DISCARD.ACTION')
    ).toBeUndefined();
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CONTACTS')
    ).toBeUndefined();

    await openDetails(wrapper, 'Confeitaria Lua');
    expect(
      buttonWithText(detailPanel(wrapper), 'PROSPECTING.LEAD_STATUS.RESTORE')
    ).toBeUndefined();
    expect(buttonWithText(detailPanel(wrapper), REFUSE_ACTION)).toBeUndefined();
  });
});

// "Não quer ser contatado" (chat#713, 26/09): a recusa da pessoa fica no lead,
// separada do status. Marcar e desfazer pedem confirmação; o selo aparece no
// card e no painel, inclusive do lead descartado.

describe('ProspectingSearchPage · não quer ser contatado', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('o painel marca com confirmação e o selo aparece no card e no painel', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.refuseLeadConsent.mockResolvedValue({
      data: { payload: sunLead({ consent_refused_at: REFUSED_AT }) },
    });
    expect(refusedBadge(leadCard(wrapper, 'Padaria Sol')).exists()).toBe(false);

    await openDetails(wrapper, 'Padaria Sol');
    await buttonWithText(detailPanel(wrapper), REFUSE_ACTION).trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(AutonomiaProspectingAPI.refuseLeadConsent).toHaveBeenCalledWith(101);
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.CONSENT_REFUSAL.REFUSE.DONE'
    );
    expect(refusedBadge(leadCard(wrapper, 'Padaria Sol')).text()).toContain(
      'PROSPECTING.CONSENT_REFUSAL.BADGE'
    );
    const panel = detailPanel(wrapper);
    expect(refusedBadge(panel).exists()).toBe(true);
    expect(buttonWithText(panel, WITHDRAW_ACTION)).toBeTruthy();
    expect(buttonWithText(panel, REFUSE_ACTION)).toBeUndefined();
  });

  it('sem confirmar não grava nada', async () => {
    const wrapper = await mountWithStatuses();
    confirmation.answer = false;

    await openDetails(wrapper, 'Padaria Sol');
    await buttonWithText(detailPanel(wrapper), REFUSE_ACTION).trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(AutonomiaProspectingAPI.refuseLeadConsent).not.toHaveBeenCalled();
  });

  it('o lead descartado que recusou mostra o selo e desfaz com confirmação', async () => {
    const wrapper = await mountSearchPage({
      payloads: {
        11: {
          search: bakerySearch(),
          leads: [
            moonLead({
              status: 'discarded',
              discard_reason: 'Sem interesse',
              consent_refused_at: REFUSED_AT,
            }),
          ],
        },
      },
    });
    AutonomiaProspectingAPI.withdrawLeadConsentRefusal.mockResolvedValue({
      data: {
        payload: moonLead({
          status: 'discarded',
          discard_reason: 'Sem interesse',
          consent_refused_at: null,
        }),
      },
    });
    const moon = leadCard(wrapper, 'Confeitaria Lua');
    expect(statusBanner(moon).text()).toContain(DISCARDED);
    expect(refusedBadge(moon).exists()).toBe(true);

    await openDetails(wrapper, 'Confeitaria Lua');
    await buttonWithText(detailPanel(wrapper), WITHDRAW_ACTION).trigger(
      'click'
    );
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(
      AutonomiaProspectingAPI.withdrawLeadConsentRefusal
    ).toHaveBeenCalledWith(103);
    expect(refusedBadge(leadCard(wrapper, 'Confeitaria Lua')).exists()).toBe(
      false
    );
  });

  it('a recusa do servidor aparece como veio', async () => {
    const wrapper = await mountWithStatuses();
    AutonomiaProspectingAPI.refuseLeadConsent.mockRejectedValue({
      response: { data: { error: 'Lead não encontrado' } },
    });

    await openDetails(wrapper, 'Padaria Sol');
    await buttonWithText(detailPanel(wrapper), REFUSE_ACTION).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Lead não encontrado');
  });
});
