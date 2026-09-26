// Caracterização dos resultados (#677): lista, ordem, refino local, contagens
// e mapa. Card do lead em .leadCard.spec.js; lote e CSV em .bulk.spec.js.
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  MapStub,
  bakerySearch,
  buttonWithTitle,
  choiceSelect,
  choose,
  gymSearch,
  hotBreadLead,
  leadCards,
  leadNames,
  mountSearchPage,
  moonLead,
  openResultFilters,
  sunLead,
} from './support/searchPageHarness';
import {
  DRAWER,
  applyFilters,
  checkYesOnly,
  rankInput,
  reviewsMinInput,
} from './support/filtersHelpers';

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

  // Mudou de propósito (#678): o seletor escolhe o campo e um botão inverte a
  // direção (ProspectingSearchPage.sort.spec.js). Cada campo começa na direção
  // de antes; "Mais antigos" virou Data invertida.
  it.each([
    ['score', ['Pão Quente', 'Padaria Sol', 'Confeitaria Lua']],
    ['created', ['Pão Quente', 'Confeitaria Lua', 'Padaria Sol']],
    ['rating', ['Padaria Sol', 'Confeitaria Lua', 'Pão Quente']],
    ['reviews', ['Pão Quente', 'Padaria Sol', 'Confeitaria Lua']],
    ['name', ['Confeitaria Lua', 'Padaria Sol', 'Pão Quente']],
    ['priority', ['Padaria Sol', 'Pão Quente', 'Confeitaria Lua']],
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
  ])('refina localmente por %s = %s', async (field, value, expected) => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, field, value);
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(expected);
    expect(
      buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.FILTER_BUTTON').text()
    ).toBe('1');
  });

  // Mudou de propósito (frente B): "aberto agora" virou caixa única "sim", como
  // no Orth; o "não" deixou de existir.
  it('refina localmente por aberto agora = sim', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await checkYesOnly(wrapper, 'OPEN_NOW');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Padaria Sol']);
  });

  // Mudou de propósito (frente B): mínimo e máximo de avaliação viraram
  // operador + estrelas; a posição máxima virou a alça direita da faixa 1 a 40.
  it.each([
    ['above', 4, ['Padaria Sol', 'Confeitaria Lua']],
    ['below', 4, ['Pão Quente']],
  ])(
    'refina localmente pela avaliação %s de %s',
    async (operator, value, expected) => {
      const wrapper = await mountSearchPage();
      await openResultFilters(wrapper);

      await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, operator);
      await choose(wrapper, `${DRAWER}.RATING.VALUE`, value);
      await applyFilters(wrapper);

      expect(leadNames(wrapper)).toEqual(expected);
    }
  );

  it('refina localmente pelo mínimo de avaliações', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await reviewsMinInput(wrapper).setValue('100');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Padaria Sol', 'Pão Quente']);
  });

  it('refina localmente pela posição máxima no Google', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await rankInput(wrapper, 'MAX_ARIA').setValue('5');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Padaria Sol', 'Pão Quente']);
  });

  it('refino local não chama a API, soma filtros no contador e acusa quando nada sobra', async () => {
    const wrapper = await mountSearchPage();
    const callsBefore = AutonomiaProspectingAPI.getSearch.mock.calls.length;
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'no');
    await applyFilters(wrapper);

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

  // Expansão de raio do Orth (#732 item 4): a busca que ficou com o raio maior
  // mostra no histórico e nos resultados o raio alcançado e o pedido.
  it('mostra o raio ampliado da busca que ficou com a expansão', async () => {
    const search = bakerySearch({
      radius: 2000,
      requested_radius: 1000,
      summary: { radius_expanded: true },
    });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [] } },
    });

    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.RADIUS_EXPANDED_VALUE'
    );
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.RADIUS_KM_VALUE');
  });

  it('o mapa segue o refino local', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'yes');
    await applyFilters(wrapper);

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
