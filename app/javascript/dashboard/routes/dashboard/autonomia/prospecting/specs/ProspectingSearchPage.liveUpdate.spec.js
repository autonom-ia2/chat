// Atualização ao vivo (#678, frente C): o servidor enriquece e verifica o WhatsApp
// em fila e avisa pelo evento prospecting.lead.updated. O card e o painel trocam
// o lead sem recarregar.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import {
  MapStub,
  bakerySearch,
  buttonWithText,
  detailPanel,
  gymSearch,
  leadCard,
  leadCards,
  mountSearchPage,
  sunLead,
} from './support/searchPageHarness';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const leadUpdated = async lead => {
  emitter.emit(BUS_EVENTS.PROSPECTING_LEAD_UPDATED, { account_id: 1, lead });
  await flushPromises();
};

const openDetails = async (wrapper, name) => {
  await buttonWithText(
    leadCard(wrapper, name),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage · lead atualizado pelo evento', () => {
  it('troca o card e o painel aberto quando o enriquecimento termina no servidor', async () => {
    const wrapper = await mountSearchPage();
    await openDetails(wrapper, 'Padaria Sol');

    await leadUpdated(
      sunLead({
        search_rank: 40,
        enrichment_status: 'completed',
        enrichment_summary: 'Padaria com café colonial',
        decision_name: 'Carlos',
      })
    );

    const card = leadCard(wrapper, 'Padaria Sol');
    expect(card.text()).toContain('Padaria com café colonial');
    expect(
      buttonWithText(card, 'PROSPECTING.SEARCH.ENRICHED').element.disabled
    ).toBe(true);
    expect(detailPanel(wrapper).text()).toContain('Carlos');
  });

  it('mantém a posição do lead nesta busca, que o evento não conhece', async () => {
    const wrapper = await mountSearchPage();

    await leadUpdated(sunLead({ search_rank: 40, name: 'Padaria Sol Nova' }));

    expect(leadCard(wrapper, 'Padaria Sol Nova')).toBeTruthy();
    const mapLead = wrapper
      .findComponent(MapStub)
      .props('leads')
      .find(lead => lead.id === 101);
    expect(mapLead).toMatchObject({ name: 'Padaria Sol Nova', search_rank: 2 });
  });

  // A nota e a prioridade também são desta busca (frente A): o evento traz as
  // da última busca que tocou o lead, e a ordem da fila não pode mudar sozinha.
  it('mantém nota, detalhe da nota e prioridade desta busca', async () => {
    const wrapper = await mountSearchPage();

    await leadUpdated(
      sunLead({
        search_rank: 40,
        score: 12,
        priority_score: 5,
        priority_position: 9,
        score_breakdown: { components: {} },
        enrichment_summary: 'Resumo novo',
      })
    );

    const mapLead = wrapper
      .findComponent(MapStub)
      .props('leads')
      .find(lead => lead.id === 101);
    expect(mapLead).toMatchObject({
      enrichment_summary: 'Resumo novo',
      search_rank: 2,
      score: 70,
      priority_score: 82,
      priority_position: 1,
      score_breakdown: sunLead().score_breakdown,
    });
  });

  it('ignora lead que não está na busca aberta', async () => {
    const wrapper = await mountSearchPage();
    const before = leadCards(wrapper).length;

    await leadUpdated(sunLead({ id: 999, name: 'Outra Padaria' }));

    expect(wrapper.text()).not.toContain('Outra Padaria');
    expect(leadCards(wrapper).length).toBe(before);
  });

  it('para de ouvir o evento quando a tela sai', async () => {
    const listeners = () =>
      emitter.all.get(BUS_EVENTS.PROSPECTING_LEAD_UPDATED) || [];
    const before = listeners().length;
    const wrapper = await mountSearchPage();
    expect(listeners()).toHaveLength(before + 1);

    wrapper.unmount();

    expect(listeners()).toHaveLength(before);
  });
});

describe('ProspectingSearchPage · WhatsApp verificado no servidor', () => {
  it('lead na fila do servidor mostra Verificando, não pede de novo pela aba, e troca pelo resultado', async () => {
    const queued = sunLead({
      whatsapp_verification_status: 'queued',
      whatsapp_verified: false,
      whatsapp_url: null,
    });
    const wrapper = await mountSearchPage({
      payloads: {
        11: { search: bakerySearch(), leads: [queued] },
        12: { search: gymSearch(), leads: [] },
      },
    });

    expect(leadCard(wrapper, 'Padaria Sol').text()).toContain(
      'PROSPECTING.SEARCH.CHECKING_WHATSAPP'
    );
    expect(AutonomiaProspectingAPI.verifyLeadWhatsApp).not.toHaveBeenCalled();

    await leadUpdated(sunLead({ whatsapp_url: 'https://wa.me/5541988887777' }));

    const card = leadCard(wrapper, 'Padaria Sol');
    expect(card.text()).not.toContain('PROSPECTING.SEARCH.CHECKING_WHATSAPP');
    expect(card.find('a[href="https://wa.me/5541988887777"]').exists()).toBe(
      true
    );
  });
});

describe('ProspectingSearchPage · enriquecer em fila', () => {
  it('pedido aceito (202) avisa que está na fila e o resultado chega pelo evento', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.enrichLead.mockResolvedValue({
      status: 202,
      data: { payload: { lead: sunLead({ enrichment_status: 'queued' }) } },
    });

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICH_LEAD'
    ).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.ENRICHMENT_QUEUED'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.ENRICHMENT_COMPLETED'
    );
    // Na fila do servidor o card continua em andamento: sem isso o botão
    // voltava a "Enriquecer" e o clique só recebia a recusa (409).
    const pending = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICHING'
    );
    expect(pending.element.disabled).toBe(true);

    await leadUpdated(
      sunLead({ enrichment_status: 'completed', enriched_cnpj: '12.345' })
    );

    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.ENRICHED'
      ).element.disabled
    ).toBe(true);
  });
});
