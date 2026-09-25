// Repetir e editar uma busca do histórico (#678, E2 frente A). "Repetir" roda
// de novo com tudo o que a busca original pediu; "Editar" abre o formulário
// com tudo preenchido: termo, local, área, modo, jogada, filtros, quantidade,
// decisor, destino no CRM e ordem. O raio é o pedido, não o expandido.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithTitle,
  choiceSelect,
  gymSearch,
  historyCards,
  mountSearchPage,
} from './support/searchPageHarness';
import { locationInput, queryInput } from './support/searchFormHelpers';
import { openFormFilters } from './support/filtersHelpers';

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

const REPEAT = 'PROSPECTING.SEARCH.REPEAT_SEARCH';
const EDIT = 'PROSPECTING.SEARCH.EDIT_SEARCH';

const EMPTY_ADVANCED_FILTERS = {
  has_website: '',
  has_phone: '',
  has_photos: '',
  open_now: '',
  has_opening_hours: '',
  rating_min: '',
  rating_max: '',
  reviews_min: '',
  outside_top: '',
  search_rank_max: '',
};

// Busca de raio que expandiu de 2 para 4 km, com jogada, filtros e CRM.
const savedRadiusSearch = () =>
  bakerySearch({
    id: 13,
    query: 'barbearia',
    location: 'Curitiba, PR',
    location_label: 'Curitiba, PR, Brasil',
    location_place_id: 'place-cwb',
    location_latitude: -25.4284,
    location_longitude: -49.2733,
    area_type: 'radius',
    radius: 4000,
    requested_radius: 2000,
    area_config: {
      center: { lat: -25.43, lng: -49.27 },
      label: 'Curitiba, PR, Brasil',
      place_id: 'place-cwb',
      radius: 4000,
    },
    requested_limit: 35,
    search_filters: { auto_expand_radius: true },
    advanced_filters: { has_website: 'no' },
    score_mode: 'gbp',
    preset_id: 'vender-site',
    decision_maker_type: 'marketing',
    crm_pipeline_id: 4,
    crm_stage_id: 41,
    sort_key: 'google_rank_asc',
  });

const expectedRadiusRequest = {
  query: 'barbearia',
  location: 'Curitiba, PR',
  radius: 2000,
  area_type: 'radius',
  area_config: {
    center: { lat: -25.43, lng: -49.27 },
    label: 'Curitiba, PR, Brasil',
    place_id: 'place-cwb',
    radius: 2000,
  },
  requested_limit: 35,
  crm_pipeline_id: 4,
  crm_stage_id: 41,
  metadata: {
    location_place_id: 'place-cwb',
    location_latitude: -25.4284,
    location_longitude: -49.2733,
    location_label: 'Curitiba, PR, Brasil',
    filters: { auto_expand_radius: true },
    decision_maker_type: 'marketing',
    advanced_filters: {
      ...EMPTY_ADVANCED_FILTERS,
      has_website: 'no',
    },
    sort_key: 'google_rank_asc',
    score_mode: 'gbp',
    preset_id: 'vender-site',
    scoring_profile_id: 9,
  },
};

const mountWithHistory = async searches => {
  AutonomiaProspectingAPI.createSearch.mockResolvedValue({
    data: { payload: { search: bakerySearch({ id: 99 }), leads: [] } },
  });
  return mountSearchPage({ searches });
};

const clickOnCard = async (wrapper, index, title) => {
  await historyCards(wrapper)
    [index].find(`button[title="${title}"]`)
    .trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage · repetir e editar busca do histórico', () => {
  beforeEach(() => {
    permission.canManage = true;
    AutonomiaProspectingAPI.createSearch.mockReset();
  });

  it('Repetir roda de novo com tudo o que a busca pediu, com o raio pedido', async () => {
    const wrapper = await mountWithHistory([
      bakerySearch(),
      savedRadiusSearch(),
    ]);

    await clickOnCard(wrapper, 1, REPEAT);

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expectedRadiusRequest
    );
    expect(AutonomiaProspectingAPI.getSearches).toHaveBeenCalledTimes(2);
  });

  it('Repetir uma busca de área visível manda os mesmos limites', async () => {
    const search = gymSearch({
      location_label: 'Londrina, PR, Brasil',
      location_place_id: 'place-ldb',
      requested_limit: 20,
      score_mode: 'general',
      decision_maker_type: 'owner',
    });
    const wrapper = await mountWithHistory([bakerySearch(), search]);

    await clickOnCard(wrapper, 1, REPEAT);

    const [request] = AutonomiaProspectingAPI.createSearch.mock.calls[0];
    expect(request.area_type).toBe('viewport');
    expect(request.area_config).toMatchObject({
      center: { lat: -23.3, lng: -51.15 },
      bounds: { north: -23.2, south: -23.4, east: -51.0, west: -51.3 },
    });
    expect(request.metadata.advanced_filters).toEqual({
      ...EMPTY_ADVANCED_FILTERS,
      has_phone: 'yes',
    });
  });

  it('Editar abre o formulário com tudo preenchido e envia o mesmo pedido', async () => {
    const wrapper = await mountWithHistory([
      bakerySearch(),
      savedRadiusSearch(),
    ]);

    await clickOnCard(wrapper, 1, EDIT);

    expect(wrapper.find('form').exists()).toBe(true);
    expect(queryInput(wrapper).element.value).toBe('barbearia');
    expect(locationInput(wrapper).element.value).toBe('Curitiba, PR');
    expect(wrapper.find('input[type="number"][max="60"]').element.value).toBe(
      '35'
    );
    expect(wrapper.find('input[type="number"][min="0.1"]').element.value).toBe(
      '2'
    );
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(true);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE').props(
        'modelValue'
      )
    ).toBe('gbp');
    expect(
      choiceSelect(wrapper, 'PROSPECTING.DECISION_MAKER.LABEL').props(
        'modelValue'
      )
    ).toBe('marketing');
    await openFormFilters(wrapper);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE').props(
        'modelValue'
      )
    ).toBe('no');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expectedRadiusRequest
    );
  });

  it('Editar não roda a busca sozinho', async () => {
    const wrapper = await mountWithHistory([
      bakerySearch(),
      savedRadiusSearch(),
    ]);

    await clickOnCard(wrapper, 1, EDIT);

    expect(AutonomiaProspectingAPI.createSearch).not.toHaveBeenCalled();
  });

  it('sem permissão de gerenciar não mostra Repetir nem Editar', async () => {
    permission.canManage = false;
    const wrapper = await mountWithHistory([bakerySearch()]);

    expect(buttonWithTitle(wrapper, REPEAT).exists()).toBe(false);
    expect(buttonWithTitle(wrapper, EDIT).exists()).toBe(false);
  });
});
