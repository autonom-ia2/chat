// Caracterização do card do lead (#677): anel de prioridade, sinais, telefone,
// WhatsApp, enriquecimento e ações do card.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithText,
  deferred,
  hotBreadLead,
  leadCard,
  mountSearchPage,
  moonLead,
  settingsFixture,
  sunLead,
} from './support/searchPageHarness';
import { ADDRESS_SEPARATOR, linkWithText } from './support/resultsHelpers';

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

describe('ProspectingSearchPage · card do lead e anel de prioridade', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('mostra o lead típico com anel, posição, sinais e ações', async () => {
    const wrapper = await mountSearchPage();
    const card = leadCard(wrapper, 'Padaria Sol');

    const ring = card.find('svg[role="img"]');
    expect(ring.attributes('aria-label')).toBe('Prioridade 82 de 100');
    expect(ring.attributes('width')).toBe('56');
    expect(ring.text()).toBe('82');

    expect(card.text()).toContain('PROSPECTING.SEARCH.PRIORITY_GOOGLE_RANK');
    expect(card.text()).toContain('PROSPECTING.SEARCH.PRIORITY_POSITION');
    expect(card.text()).toContain(
      'PROSPECTING.SEARCH.PRIORITY_FIRST_CALL_SHORT'
    );
    expect(card.text()).toContain('Lead muito quente');
    expect(card.text()).toContain(`Rua A, 10${ADDRESS_SEPARATOR}Curitiba PR`);

    const site = linkWithText(card, 'Abrir site');
    expect(site.attributes('href')).toBe('https://sol.com.br');
    expect(site.attributes('target')).toBe('_blank');
    const signals = card
      .findAll('span.rounded-full.border')
      .map(signal => signal.text());
    expect(signals).toEqual(['Tem fone', '#2 Google', '4.7 estrelas']);

    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.OPEN_MAP').attributes('href')
    ).toBe('https://www.google.com/maps/search/?api=1&query=-25.4%2C-49.2');
    const whatsapp = linkWithText(card, 'PROSPECTING.SEARCH.WHATSAPP');
    expect(whatsapp.attributes('href')).toBe('https://wa.me/5541999990001');
    expect(whatsapp.classes()).toContain('bg-n-teal-9');
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.CALL').attributes('href')
    ).toBe('tel:+5541999990001');
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.OPEN_CONTACT').attributes('href')
    ).toBe('/app/accounts/1/contacts/900');

    const enrich = buttonWithText(card, 'PROSPECTING.SEARCH.ENRICH_LEAD');
    expect(enrich.element.disabled).toBe(false);
    expect(enrich.attributes('title')).toBe('PROSPECTING.SEARCH.ENRICH_LEAD');
    expect(
      buttonWithText(card, 'PROSPECTING.SEARCH.CREATE_CRM_CARD').element
        .disabled
    ).toBe(false);
    expect(card.find('input[type="checkbox"]').element.checked).toBe(false);
  });

  it('lead sem site e com card no CRM: sem link de site, sem WhatsApp e com link do card', async () => {
    const wrapper = await mountSearchPage();
    const card = leadCard(wrapper, 'Pão Quente');

    expect(card.find('svg[role="img"]').attributes('aria-label')).toBe(
      'Prioridade 40 de 100'
    );
    expect(card.text()).toContain('Lead morno');
    expect(card.text()).not.toContain(
      'PROSPECTING.SEARCH.PRIORITY_FIRST_CALL_SHORT'
    );
    // O v-for dos sinais renderiza um <a> por sinal; só o de site com site aparece.
    expect(linkWithText(card, 'Sem site').attributes('style')).toContain(
      'display: none'
    );
    expect(
      card.findAll('span.rounded-full.border').map(signal => signal.text())
    ).toEqual(['Sem site', 'Tem fone', '#5 Google', '3.9 estrelas']);
    expect(card.text()).toContain('PROSPECTING.SEARCH.NO_WHATSAPP');
    expect(linkWithText(card, 'PROSPECTING.SEARCH.WHATSAPP')).toBeUndefined();
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.CALL').attributes('href')
    ).toBe('tel:+554133330002');
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.OPEN_MAP').attributes('href')
    ).toBe(
      `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
        `Pão Quente Rua B, 20${ADDRESS_SEPARATOR}Curitiba PR`
      )}`
    );
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.OPEN_CRM_CARD').attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=555');
    expect(
      buttonWithText(card, 'PROSPECTING.SEARCH.CREATE_CRM_CARD')
    ).toBeUndefined();
    const enrich = buttonWithText(card, 'PROSPECTING.SEARCH.ENRICH_LEAD');
    expect(enrich.element.disabled).toBe(true);
    expect(enrich.attributes('title')).toBe(
      'PROSPECTING.SEARCH.ENRICHMENT_NO_SITE'
    );
  });

  it('lead enriquecido e sem fone: bloco de enriquecimento, sem ligar e sem WhatsApp', async () => {
    const wrapper = await mountSearchPage();
    const card = leadCard(wrapper, 'Confeitaria Lua');

    expect(card.text()).toContain('Prioridade baixa');
    expect(card.text()).toContain('PROSPECTING.SEARCH.ENRICHMENT_TITLE');
    expect(card.text()).toContain('PROSPECTING.SEARCH.DECISION_MAKER:');
    expect(card.text()).toContain('Ana');
    expect(card.text()).toContain('· Dona');
    expect(card.text()).toContain('Atende eventos');
    expect(card.text()).toContain(`Rua C, 30${ADDRESS_SEPARATOR}Curitiba`);
    expect(card.text()).toContain('PROSPECTING.SEARCH.NO_WHATSAPP');
    expect(linkWithText(card, 'PROSPECTING.SEARCH.CALL')).toBeUndefined();
    const enriched = buttonWithText(card, 'PROSPECTING.SEARCH.ENRICHED');
    expect(enriched.element.disabled).toBe(true);
    expect(enriched.attributes('title')).toBe('PROSPECTING.SEARCH.ENRICHED');
  });

  it('lead sem nota mostra o anel vazio e nenhum título de prioridade', async () => {
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [sunLead({ priority_score: null, score: null })],
        },
      },
    });
    const card = leadCard(wrapper, 'Padaria Sol');

    expect(card.find('svg').exists()).toBe(false);
    expect(card.find('div.rounded-full.bg-n-solid-2').text()).toBe('-');
    [
      'Lead muito quente',
      'Oportunidade alta',
      'Lead morno',
      'Prioridade baixa',
    ].forEach(title => expect(card.text()).not.toContain(title));
  });

  it('com a pesquisa desligada o enriquecer fica bloqueado com o motivo', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({ research_enabled: false }),
    });
    const enrich = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.ENRICH_LEAD'
    );

    expect(enrich.element.disabled).toBe(true);
    expect(enrich.attributes('title')).toBe(
      'PROSPECTING.SEARCH.ENRICHMENT_DISABLED'
    );
  });

  it('verifica o WhatsApp dos leads com fone ainda não verificado e troca pelo link confirmado', async () => {
    const search = bakerySearch();
    const pending = deferred();
    AutonomiaProspectingAPI.verifyLeadWhatsApp.mockReturnValueOnce(
      pending.promise
    );
    const mountPromise = mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [
            sunLead({
              whatsapp_verification_status: null,
              whatsapp_verified: null,
            }),
            hotBreadLead(),
            moonLead(),
          ],
        },
      },
    });
    const wrapper = await mountPromise;

    expect(AutonomiaProspectingAPI.verifyLeadWhatsApp).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.verifyLeadWhatsApp).toHaveBeenCalledWith(
      101
    );
    expect(leadCard(wrapper, 'Padaria Sol').text()).toContain(
      'PROSPECTING.SEARCH.CHECKING_WHATSAPP'
    );

    pending.resolve({
      data: {
        payload: {
          lead: sunLead({
            whatsapp_verification_status: 'verified',
            whatsapp_verified: true,
            whatsapp_url: 'https://wa.me/5541999990001?text=oi',
          }),
        },
      },
    });
    await flushPromises();

    const card = leadCard(wrapper, 'Padaria Sol');
    expect(card.text()).not.toContain('PROSPECTING.SEARCH.CHECKING_WHATSAPP');
    expect(
      linkWithText(card, 'PROSPECTING.SEARCH.WHATSAPP').attributes('href')
    ).toBe('https://wa.me/5541999990001?text=oi');
  });

  it('sem permissão de gerenciar não verifica WhatsApp nem mostra enriquecer, criar card ou lote', async () => {
    permission.canManage = false;
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [sunLead({ whatsapp_verification_status: null })],
        },
      },
    });
    const card = leadCard(wrapper, 'Padaria Sol');

    expect(AutonomiaProspectingAPI.verifyLeadWhatsApp).not.toHaveBeenCalled();
    expect(
      buttonWithText(card, 'PROSPECTING.SEARCH.ENRICH_LEAD')
    ).toBeUndefined();
    expect(
      buttonWithText(card, 'PROSPECTING.SEARCH.CREATE_CRM_CARD')
    ).toBeUndefined();

    await card.find('input[type="checkbox"]').trigger('change');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.SELECTED_COUNT');
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS')
    ).toBeUndefined();
  });
});
