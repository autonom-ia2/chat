// Caracterização do painel lateral de detalhe do lead e do enriquecimento (#677).
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import {
  MapStub,
  buttonWithText,
  deferred,
  detailPanel,
  leadCard,
  mountSearchPage,
  sunLead,
  toggleNewSearch,
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
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const openDetails = async (wrapper, name) => {
  await buttonWithText(
    leadCard(wrapper, name),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
};

const linkWithText = (element, text) =>
  element.findAll('a').find(link => link.text().trim() === text);

const blockValue = (panel, label) =>
  panel
    .findAll('div.rounded-md.p-3')
    .find(block => block.text().includes(label))
    .find('div.mt-2')
    .text();

describe('ProspectingSearchPage · painel de detalhe do lead', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('abre pelo card com cabeçalho, anel grande, avaliação da nota e contato', async () => {
    const wrapper = await mountSearchPage();
    expect(detailPanel(wrapper).exists()).toBe(false);

    await openDetails(wrapper, 'Padaria Sol');
    const panel = detailPanel(wrapper);

    expect(panel.find('h2').text()).toBe('Padaria Sol');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.PRIORITY_GOOGLE_RANK');
    expect(panel.text()).toContain(
      'PROSPECTING.SEARCH.PRIORITY_POSITION_IN_LIST'
    );
    expect(panel.text()).toContain('PROSPECTING.SEARCH.PRIORITY_FIRST_CALL');
    expect(panel.text()).toContain(
      'Rua A, 10PROSPECTING.SEARCH.ADDRESS_SEPARATORCuritiba PR'
    );

    const ring = panel.find('svg[role="img"]');
    expect(ring.attributes('width')).toBe('92');
    expect(ring.attributes('aria-label')).toBe('Prioridade 82 de 100');
    expect(panel.find('div.rounded-xl').classes()).toContain('bg-n-teal-2');
    expect(panel.text()).toContain('Lead muito quente');
    expect(panel.text()).toContain('Bem avaliada e sem reservas online');
    expect(
      panel.findAll('span.rounded-full.border').map(signal => signal.text())
    ).toEqual(['Abrir site', 'Tem fone', '#2 Google', '4.7 estrelas']);

    expect(panel.text()).toContain('PROSPECTING.SEARCH.SCORE_EVALUATION_TITLE');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.SCORE_VALUE');
    expect(panel.text()).toContain(
      'PROSPECTING.SEARCH.SCORE_COMPONENTS.RATING'
    );
    expect(panel.text()).toContain(
      'PROSPECTING.SEARCH.SCORE_COMPONENTS.WEBSITE'
    );
    expect(panel.text()).toContain('30%');
    expect(panel.text()).toContain('28.2');
    expect(panel.text()).toContain('20%');
    expect(panel.text()).toContain(
      'PROSPECTING.SEARCH.NEGATIVE_FACTORS.MISSING_PHOTOS'
    );
    expect(panel.text()).toContain(
      'PROSPECTING.SEARCH.NEGATIVE_FACTORS.LOW_REVIEWS'
    );
    expect(panel.text()).toContain('-5');

    expect(panel.text()).toContain('(41) 99999-0001');
    expect(linkWithText(panel, 'https://sol.com.br').attributes('href')).toBe(
      'https://sol.com.br'
    );
    expect(panel.text()).toContain('PROSPECTING.SEARCH.RATING_LABEL');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.REVIEWS_LABEL');
    expect(blockValue(panel, 'PROSPECTING.SEARCH.FIELDS.CATEGORY')).toBe(
      'Padaria'
    );
    expect(blockValue(panel, 'PROSPECTING.SEARCH.FIELDS.CRM_STAGE')).toBe(
      'Novo'
    );
    expect(blockValue(panel, 'PROSPECTING.SEARCH.COORDINATES')).toBe(
      '-25.4, -49.2'
    );
    expect(panel.text()).not.toContain('PROSPECTING.QUALITY.DISCARD_REASON');
    expect(panel.text()).not.toContain('PROSPECTING.SEARCH.ENRICHMENT_TITLE');
  });

  it('mostra só as 5 avaliações mais recentes, com autor, tempo e texto em cada formato', async () => {
    const wrapper = await mountSearchPage();
    await openDetails(wrapper, 'Padaria Sol');
    const reviews = detailPanel(wrapper).findAll('li.border-b');

    expect(detailPanel(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.LATEST_REVIEWS_TITLE'
    );
    expect(reviews).toHaveLength(5);
    expect(reviews[0].text()).toContain('5');
    expect(reviews[0].text()).toContain('Maria');
    expect(reviews[0].text()).toContain('há 2 dias');
    expect(reviews[0].text()).toContain('Pão ótimo');
    expect(reviews[1].text()).toContain('João');
    expect(reviews[1].text()).toContain('há 1 semana');
    expect(reviews[1].text()).toContain('Bom café');
    expect(reviews[2].find('p').text()).toBe('Texto original');
    expect(reviews[3].find('p').text()).toBe('Comentário antigo');
    expect(reviews[4].find('p').text()).toBe('-');
    expect(detailPanel(wrapper).text()).not.toContain('Sexta avaliação');
  });

  it('lead com card no CRM, motivo de descarte e sem coordenadas', async () => {
    const wrapper = await mountSearchPage();
    await openDetails(wrapper, 'Pão Quente');
    const panel = detailPanel(wrapper);

    expect(panel.find('div.rounded-xl').classes()).toContain('bg-n-amber-2');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.SCORE_BASE');
    expect(panel.text()).not.toContain(
      'PROSPECTING.SEARCH.SCORE_EVALUATION_TITLE'
    );
    expect(panel.text()).not.toContain(
      'PROSPECTING.SEARCH.LATEST_REVIEWS_TITLE'
    );
    expect(panel.text()).toContain('PROSPECTING.QUALITY.DISCARD_REASON');
    expect(panel.text()).toContain('Fechado aos domingos');
    expect(blockValue(panel, 'PROSPECTING.SEARCH.COORDINATES')).toBe('-');
    expect(blockValue(panel, 'PROSPECTING.SEARCH.FIELDS.CATEGORY')).toBe('-');
    expect(
      linkWithText(panel, 'PROSPECTING.SEARCH.OPEN_CRM_CARD').attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=555');
    expect(
      buttonWithText(panel, 'PROSPECTING.SEARCH.CREATE_CRM_CARD')
    ).toBeUndefined();
    expect(
      linkWithText(panel, 'PROSPECTING.SEARCH.OPEN_CONTACT')
    ).toBeUndefined();
  });

  it('abre pelo marcador do mapa e mostra os dados do enriquecimento', async () => {
    const wrapper = await mountSearchPage();

    wrapper.findComponent(MapStub).vm.$emit('selectLead', { id: 103 });
    await flushPromises();
    const panel = detailPanel(wrapper);

    expect(panel.find('h2').text()).toBe('Confeitaria Lua');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.ENRICHMENT_TITLE');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.ENRICHMENT_SUMMARY');
    expect(panel.text()).toContain('Atende eventos');
    expect(panel.text()).toContain('Ana');
    expect(panel.text()).toContain('· Dona');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.ENRICHED_EMAIL:');
    expect(panel.text()).toContain('ana@lua.com');
    expect(panel.text()).toContain('PROSPECTING.SEARCH.ENRICHED_INSTAGRAM:');
    expect(panel.text()).not.toContain('PROSPECTING.SEARCH.ENRICHED_CNPJ');
    expect(blockValue(panel, 'PROSPECTING.SEARCH.COORDINATES')).toBe(
      '-25.41, -49.21'
    );
  });

  it('fecha pelo botão, pelo fundo e ao abrir uma nova busca', async () => {
    const wrapper = await mountSearchPage();

    await openDetails(wrapper, 'Padaria Sol');
    await detailPanel(wrapper)
      .find('button[title="PROSPECTING.SEARCH.CLOSE_DETAILS"]')
      .trigger('click');
    expect(detailPanel(wrapper).exists()).toBe(false);

    await openDetails(wrapper, 'Padaria Sol');
    await wrapper.find('div.fixed.inset-0').trigger('click');
    expect(detailPanel(wrapper).exists()).toBe(false);

    await openDetails(wrapper, 'Padaria Sol');
    await toggleNewSearch(wrapper);
    expect(detailPanel(wrapper).exists()).toBe(false);
    await toggleNewSearch(wrapper);
    expect(detailPanel(wrapper).exists()).toBe(false);
  });

  it('cria o card no CRM pelo rodapé do painel', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createLeadCrmCard.mockResolvedValue({
      data: { payload: { lead: sunLead({ crm_card_id: 321 }) } },
    });

    await openDetails(wrapper, 'Padaria Sol');
    await buttonWithText(
      detailPanel(wrapper),
      'PROSPECTING.SEARCH.CREATE_CRM_CARD'
    ).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard).toHaveBeenCalledWith(
      101,
      {
        pipeline_id: 3,
        stage_id: 31,
      }
    );
    expect(
      linkWithText(
        detailPanel(wrapper),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=321');
    expect(
      linkWithText(
        detailPanel(wrapper),
        'PROSPECTING.SEARCH.OPEN_CONTACT'
      ).attributes('href')
    ).toBe('/app/accounts/1/contacts/900');
  });

  it('sem permissão de gerenciar o painel não oferece criar card', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage();

    await openDetails(wrapper, 'Padaria Sol');

    expect(
      buttonWithText(detailPanel(wrapper), 'PROSPECTING.SEARCH.CREATE_CRM_CARD')
    ).toBeUndefined();
  });
});

describe('ProspectingSearchPage · enriquecer lead', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('enriquece pelo card, mostra o andamento e o painel passa a exibir o resultado', async () => {
    const wrapper = await mountSearchPage();
    const pending = deferred();
    AutonomiaProspectingAPI.enrichLead.mockReturnValue(pending.promise);
    await openDetails(wrapper, 'Padaria Sol');

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICH_LEAD'
    ).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.enrichLead).toHaveBeenCalledWith(101);
    const running = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICHING'
    );
    expect(running.element.disabled).toBe(true);

    pending.resolve({
      data: {
        payload: {
          lead: sunLead({
            enrichment_status: 'completed',
            decision_name: 'Carlos',
            enriched_cnpj: '12.345.678/0001-90',
          }),
        },
      },
    });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.ENRICHMENT_COMPLETED'
    );
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.ENRICHED'
      ).element.disabled
    ).toBe(true);
    const panel = detailPanel(wrapper);
    expect(panel.text()).toContain('PROSPECTING.SEARCH.ENRICHMENT_TITLE');
    expect(panel.text()).toContain('Carlos');
    expect(panel.text()).toContain('12.345.678/0001-90');
  });

  it('marca falha e avisa o erro da API quando o enriquecimento falha', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.enrichLead.mockRejectedValue({
      response: { data: { error: 'Site fora do ar' } },
    });

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICH_LEAD'
    ).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Site fora do ar');
    const retry = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICH_LEAD'
    );
    expect(retry.element.disabled).toBe(false);
  });
});
