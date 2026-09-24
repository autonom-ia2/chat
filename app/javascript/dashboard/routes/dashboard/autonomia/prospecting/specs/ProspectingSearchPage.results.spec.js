// Caracterização dos resultados (#677): lista, ordem, refino local, contagens,
// mapa, card do lead com anel de prioridade e ações em lote.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import {
  MapStub,
  bakerySearch,
  buttonWithText,
  buttonWithTitle,
  choiceSelect,
  choose,
  deferred,
  gymSearch,
  hotBreadLead,
  leadCard,
  leadCards,
  leadNames,
  mountSearchPage,
  moonLead,
  openResultFilters,
  settingsFixture,
  sunLead,
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

const ADDRESS_SEPARATOR = 'PROSPECTING.SEARCH.ADDRESS_SEPARATOR';

const numberFilterInputs = wrapper => wrapper.findAll('input[type="number"]');

const leadCheckbox = (wrapper, name) =>
  leadCard(wrapper, name).find('input[type="checkbox"]');

const linkWithText = (element, text) =>
  element.findAll('a').find(link => link.text().trim() === text);

const readBlob = blob =>
  new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });

const captureCsvDownload = () => {
  const download = { blob: null, fileName: null, clicks: 0 };
  URL.createObjectURL = vi.fn(blob => {
    download.blob = blob;
    return 'blob:csv';
  });
  URL.revokeObjectURL = vi.fn();
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    function captureClick() {
      download.fileName = this.download;
      download.clicks += 1;
    }
  );
  return download;
};

describe('ProspectingSearchPage · resultados', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('lista os leads pela posição de prioridade e mostra a contagem visível', async () => {
    const wrapper = await mountSearchPage();

    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Pão Quente',
      'Confeitaria Lua',
    ]);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.VISIBLE_COUNT');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.MAP_TITLE');
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SORT')
    ).toBeUndefined();
  });

  it('busca aberta sem leads mostra o vazio de resultados', async () => {
    const wrapper = await mountSearchPage({ searches: [gymSearch()] });

    expect(leadCards(wrapper)).toHaveLength(0);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_EMPTY');
  });

  it('oferece as ordens na ordem atual da tela', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    const sort = choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SORT');
    expect(sort.props('modelValue')).toBe('priority_desc');
    expect(sort.props('options').map(option => option.value)).toEqual([
      'priority_desc',
      'score_desc',
      'created_desc',
      'created_asc',
      'rating_desc',
      'reviews_desc',
      'name_asc',
    ]);
  });

  it.each([
    ['score_desc', ['Pão Quente', 'Padaria Sol', 'Confeitaria Lua']],
    ['created_desc', ['Pão Quente', 'Confeitaria Lua', 'Padaria Sol']],
    ['created_asc', ['Padaria Sol', 'Confeitaria Lua', 'Pão Quente']],
    ['rating_desc', ['Padaria Sol', 'Confeitaria Lua', 'Pão Quente']],
    ['reviews_desc', ['Pão Quente', 'Padaria Sol', 'Confeitaria Lua']],
    ['name_asc', ['Confeitaria Lua', 'Padaria Sol', 'Pão Quente']],
    ['priority_desc', ['Padaria Sol', 'Pão Quente', 'Confeitaria Lua']],
  ])('ordena por %s', async (sortKey, expected) => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.SORT', sortKey);

    expect(leadNames(wrapper)).toEqual(expected);
  });

  it('sem posição de prioridade desempata pela nota de prioridade', async () => {
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [
            sunLead({ priority_position: null, priority_score: 30 }),
            hotBreadLead({ priority_position: null, priority_score: 90 }),
            moonLead({ priority_position: 1 }),
          ],
        },
      },
    });

    expect(leadNames(wrapper)).toEqual([
      'Confeitaria Lua',
      'Pão Quente',
      'Padaria Sol',
    ]);
  });

  it.each([
    ['PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no', ['Pão Quente']],
    [
      'PROSPECTING.SEARCH.FIELDS.HAS_SITE',
      'yes',
      ['Padaria Sol', 'Confeitaria Lua'],
    ],
    ['PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'no', ['Confeitaria Lua']],
    [
      'PROSPECTING.SEARCH.FIELDS.HAS_PHOTOS',
      'yes',
      ['Padaria Sol', 'Confeitaria Lua'],
    ],
    ['PROSPECTING.SEARCH.FIELDS.OPEN_NOW', 'yes', ['Padaria Sol']],
    ['PROSPECTING.SEARCH.FIELDS.OPEN_NOW', 'no', ['Pão Quente']],
  ])('refina localmente por %s = %s', async (field, value, expected) => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, field, value);

    expect(leadNames(wrapper)).toEqual(expected);
    expect(
      buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.FILTER_BUTTON').text()
    ).toBe('1');
  });

  it.each([
    [0, '4', ['Padaria Sol', 'Confeitaria Lua']],
    [1, '4', ['Pão Quente']],
    [2, '100', ['Padaria Sol', 'Pão Quente']],
    [3, '5', ['Padaria Sol', 'Pão Quente']],
  ])(
    'refina localmente pelo campo numérico %i = %s',
    async (index, value, expected) => {
      const wrapper = await mountSearchPage();
      await openResultFilters(wrapper);

      await numberFilterInputs(wrapper)[index].setValue(value);

      expect(leadNames(wrapper)).toEqual(expected);
    }
  );

  it('refino local não chama a API, soma filtros no contador e acusa quando nada sobra', async () => {
    const wrapper = await mountSearchPage();
    const callsBefore = AutonomiaProspectingAPI.getSearch.mock.calls.length;
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'no');

    expect(leadCards(wrapper)).toHaveLength(0);
    expect(wrapper.text()).toContain('PROSPECTING.QUALITY.NO_STATUS_RESULTS');
    expect(
      buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.FILTER_BUTTON').text()
    ).toBe('2');
    expect(AutonomiaProspectingAPI.getSearch.mock.calls.length).toBe(
      callsBefore
    );
    expect(
      buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').element.disabled
    ).toBe(true);
  });

  it('monta o mapa da busca por raio com o centro, o raio e só os leads com coordenadas', async () => {
    const wrapper = await mountSearchPage();

    const map = wrapper.findComponent(MapStub);
    expect(map.props('apiKey')).toBe('chave-navegador');
    expect(map.props('center')).toEqual({ lat: -25.43, lng: -49.27 });
    expect(map.props('radius')).toBe(2000);
    expect(map.props('bounds')).toBeNull();
    expect(map.props('fitOnRender')).toBe(true);
    expect(map.props('leads').map(lead => lead.id)).toEqual([101, 103]);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RADIUS_KM_VALUE');
  });

  it('o mapa segue o refino local', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'yes');

    expect(
      wrapper
        .findComponent(MapStub)
        .props('leads')
        .map(lead => lead.id)
    ).toEqual([101]);
  });

  it('monta o mapa da busca por área visível com os limites salvos e sem raio', async () => {
    const search = gymSearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 12: { search, leads: [] } },
    });

    const map = wrapper.findComponent(MapStub);
    expect(map.props('center')).toEqual({ lat: -23.3, lng: -51.15 });
    expect(map.props('radius')).toBe(0);
    expect(map.props('bounds')).toEqual(search.area_config.bounds);
    expect(map.props('leads')).toEqual([]);
  });

  it('usa as coordenadas do local quando a busca não tem centro salvo', async () => {
    const search = bakerySearch({
      area_config: {},
      radius: null,
      location_latitude: '-25.5',
      location_longitude: '-49.3',
    });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [] } },
    });

    const map = wrapper.findComponent(MapStub);
    expect(map.props('center')).toEqual({ lat: -25.5, lng: -49.3 });
    expect(map.props('radius')).toBe(1000);
  });

  it('sem centro e sem leads com coordenadas mostra o aviso no lugar do mapa', async () => {
    const search = bakerySearch({ area_config: {} });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [hotBreadLead()] } },
    });

    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.MAP_NO_COORDINATES');
  });
});

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

describe('ProspectingSearchPage · ações em lote', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('seleciona um lead, seleciona todos os visíveis e limpa a seleção', async () => {
    const wrapper = await mountSearchPage();
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.SELECTED_COUNT');

    await leadCheckbox(wrapper, 'Pão Quente').trigger('change');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.SELECTED_COUNT');
    expect(leadCheckbox(wrapper, 'Pão Quente').element.checked).toBe(true);
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS')
    ).toBeTruthy();

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    expect(
      leadCards(wrapper).map(
        card => card.find('input[type="checkbox"]').element.checked
      )
    ).toEqual([true, true, true]);

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    expect(
      leadCards(wrapper).map(
        card => card.find('input[type="checkbox"]').element.checked
      )
    ).toEqual([false, false, false]);
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.SELECTED_COUNT');
  });

  it('envia ao CRM em lote só os leads sem card, em sequência, no funil e estágio padrão', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createLeadCrmCard.mockImplementation(leadId =>
      Promise.resolve({
        data: {
          payload: {
            lead: (leadId === 101 ? sunLead : moonLead)({
              crm_card_id: leadId * 10,
            }),
          },
        },
      })
    );

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard.mock.calls).toEqual([
      [101, { pipeline_id: 3, stage_id: 31 }],
      [103, { pipeline_id: 3, stage_id: 31 }],
    ]);
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.CRM_CARD_CREATED'
    );
    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=1010');
  });

  it('usa o funil e o estágio configurados na própria busca', async () => {
    const search = bakerySearch({ crm_pipeline_id: 4, crm_stage_id: 41 });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });
    AutonomiaProspectingAPI.createLeadCrmCard.mockResolvedValue({
      data: { payload: { lead: sunLead({ crm_card_id: 9 }) } },
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard).toHaveBeenCalledWith(
      101,
      {
        pipeline_id: 4,
        stage_id: 41,
      }
    );
  });

  it('sem funil definido bloqueia o envio ao CRM no lote e no card', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({
        default_crm_pipeline_id: null,
        default_crm_stage_id: null,
      }),
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').element
        .disabled
    ).toBe(true);
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.CREATE_CRM_CARD'
      ).element.disabled
    ).toBe(true);
  });

  it('cria o card de um lead pelo próprio card e troca o botão pelo link', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createLeadCrmCard.mockResolvedValue({
      data: { payload: { lead: sunLead({ crm_card_id: 777 }) } },
    });

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
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
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.CRM_CARD_CREATED'
    );
    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=777');
  });

  it('mostra criando enquanto espera e avisa o erro da API ao criar o card', async () => {
    const wrapper = await mountSearchPage();
    const pending = deferred();
    AutonomiaProspectingAPI.createLeadCrmCard.mockReturnValue(pending.promise);

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.CREATE_CRM_CARD'
    ).trigger('click');
    await flushPromises();
    const creating = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.CREATING_CRM_CARD'
    );
    expect(creating.element.disabled).toBe(true);

    pending.reject({ response: { data: { error: 'Estágio inválido' } } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Estágio inválido');
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.CREATE_CRM_CARD'
      ).element.disabled
    ).toBe(false);
  });

  it('exporta CSV de todos os leads visíveis, na ordem da tela', async () => {
    const wrapper = await mountSearchPage();
    const download = captureCsvDownload();

    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );
    const csv = await readBlob(download.blob);

    expect(download.fileName).toBe('prospeccao-11.csv');
    expect(download.clicks).toBe(1);
    expect(download.blob.type).toBe('text/csv;charset=utf-8;');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:csv');
    expect(csv.split('\n')).toEqual([
      'name,phone,website,address,status,source',
      `"Padaria Sol","(41) 99999-0001","https://sol.com.br","Rua A, 10${ADDRESS_SEPARATOR}Curitiba PR","new","Google Maps"`,
      `"Pão Quente","4133330002","","Rua B, 20${ADDRESS_SEPARATOR}Curitiba PR","contacted","google_places"`,
      `"Confeitaria Lua","","https://lua.com.br","Rua C, 30${ADDRESS_SEPARATOR}Curitiba","new","google_places"`,
    ]);
  });

  it('exporta só os selecionados e escapa aspas', async () => {
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [sunLead({ name: 'Padaria "Sol"' }), hotBreadLead()],
        },
      },
    });
    const download = captureCsvDownload();

    await leadCheckbox(wrapper, 'Padaria "Sol"').trigger('change');
    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );
    const lines = (await readBlob(download.blob)).split('\n');

    expect(lines).toHaveLength(2);
    expect(lines[1].startsWith('"Padaria ""Sol""",')).toBe(true);
  });
});
