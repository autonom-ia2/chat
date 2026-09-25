// Caracterização do formulário de nova busca (#677): fixa o comportamento
// atual antes da quebra da página em componentes.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import {
  MapStub,
  bakerySearch,
  buttonWithText,
  choiceSelect,
  choose,
  leadNames,
  mountSearchPage,
  openResultFilters,
  settingsFixture,
  sunLead,
  toggleNewSearch,
  waitLocationDebounce,
} from './support/searchPageHarness';
import {
  DRAWER,
  applyFilters,
  openFormFilters,
  rankInput,
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

const LOCATION_DETAILS = {
  label: 'Curitiba, PR, Brasil',
  place_id: 'place-cwb',
  latitude: '-25.4284',
  longitude: '-49.2733',
};

const queryInput = wrapper =>
  wrapper.find('input[placeholder="PROSPECTING.SEARCH.QUERY_PLACEHOLDER"]');
const locationInput = wrapper =>
  wrapper.find('input[placeholder="PROSPECTING.SEARCH.LOCATION_PLACEHOLDER"]');
const radiusInput = wrapper => wrapper.find('input[min="0.1"]');
const limitInput = wrapper => wrapper.find('input[max="60"]');
const autoExpandInput = wrapper => wrapper.find('form input[type="checkbox"]');
const submitButton = wrapper => wrapper.find('button[type="submit"]');

const openFormWithoutHistory = async (options = {}) => {
  const wrapper = await mountSearchPage({ searches: [], ...options });
  await toggleNewSearch(wrapper);
  return wrapper;
};

const confirmCuritiba = async wrapper => {
  AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
    data: {
      payload: [
        { text: 'Curitiba, PR', place_id: 'place-cwb' },
        { text: 'Curitiba, PR (duplicada)', place_id: 'place-cwb' },
        { text: 'Curitibanos, SC', place_id: 'place-cbs' },
      ],
    },
  });
  AutonomiaProspectingAPI.getLocationDetails.mockResolvedValue({
    data: { payload: LOCATION_DETAILS },
  });
  await locationInput(wrapper).setValue('Curi');
  await waitLocationDebounce();
  await buttonWithText(wrapper, 'Curitiba, PR').trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage · formulário de nova busca', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('abre com os valores iniciais e o modo de pesquisa vindo das configurações', async () => {
    const wrapper = await openFormWithoutHistory();

    expect(wrapper.find('form').exists()).toBe(true);
    expect(wrapper.find('header button').text()).toBe(
      'PROSPECTING.SEARCH.BACK_TO_RESULTS'
    );
    expect(queryInput(wrapper).element.value).toBe('');
    expect(locationInput(wrapper).element.value).toBe('');
    expect(radiusInput(wrapper).element.value).toBe('1');
    expect(limitInput(wrapper).element.value).toBe('20');
    expect(autoExpandInput(wrapper).element.checked).toBe(true);
    expect(autoExpandInput(wrapper).element.disabled).toBe(false);

    const area = choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.AREA_TYPE');
    expect(area.props('modelValue')).toBe('radius');
    // Área desenhada (#678, E2 frente B): círculo, retângulo e polígono.
    expect(area.props('options').map(option => option.value)).toEqual([
      'radius',
      'viewport',
      'circle',
      'rectangle',
      'polygon',
    ]);

    const mode = choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE');
    expect(mode.props('modelValue')).toBe('general');
    expect(mode.props('options').map(option => option.value)).toEqual([
      'gbp',
      'general',
    ]);
    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.SCORE_MODE_GENERAL_HINT'
    );
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_RADIUS_HINT');
    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.AUTOCOMPLETE_READY_HINT'
    );
    expect(submitButton(wrapper).element.disabled).toBe(true);
    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
  });

  it('cai no modo gbp sem modo nas configurações e ignora default_limit ao abrir o formulário', async () => {
    const wrapper = await openFormWithoutHistory({
      settings: settingsFixture({
        search_score_mode: undefined,
        default_limit: 45,
        platform_google_places_configured: false,
      }),
    });

    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE').props(
        'modelValue'
      )
    ).toBe('gbp');
    expect(limitInput(wrapper).element.value).toBe('20');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.SCORE_MODE_GBP_HINT');
    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.AUTOCOMPLETE_DISABLED_HINT'
    );
  });

  it('esconde o botão de nova busca sem permissão de gerenciar', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage({ searches: [] });

    expect(wrapper.find('header button').exists()).toBe(false);
    expect(wrapper.find('form').exists()).toBe(false);
  });

  it('só busca sugestões de local a partir de 3 letras, com espera, e remove sugestões repetidas', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
      data: {
        payload: [
          { text: 'Curitiba, PR', place_id: 'place-cwb' },
          { text: 'Curitiba, PR (duplicada)', place_id: 'place-cwb' },
          { text: 'Curitibanos, SC', place_id: 'place-cbs' },
        ],
      },
    });

    await locationInput(wrapper).setValue('Cu');
    await waitLocationDebounce();
    expect(
      AutonomiaProspectingAPI.getLocationSuggestions
    ).not.toHaveBeenCalled();

    await locationInput(wrapper).setValue('Curi');
    expect(
      AutonomiaProspectingAPI.getLocationSuggestions
    ).not.toHaveBeenCalled();
    await waitLocationDebounce();

    expect(
      AutonomiaProspectingAPI.getLocationSuggestions
    ).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.getLocationSuggestions).toHaveBeenCalledWith(
      'Curi'
    );
    expect(buttonWithText(wrapper, 'Curitiba, PR')).toBeTruthy();
    expect(buttonWithText(wrapper, 'Curitibanos, SC')).toBeTruthy();
    expect(buttonWithText(wrapper, 'Curitiba, PR (duplicada)')).toBeUndefined();
  });

  it('confirma o local pelo detalhe do Google e monta o mapa de raio', async () => {
    const wrapper = await openFormWithoutHistory();
    await confirmCuritiba(wrapper);

    expect(AutonomiaProspectingAPI.getLocationDetails).toHaveBeenCalledWith(
      'place-cwb'
    );
    expect(locationInput(wrapper).element.value).toBe('Curitiba, PR, Brasil');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.LOCATION_CONFIRMED');
    expect(wrapper.text()).toContain('Curitiba, PR, Brasil');
    expect(buttonWithText(wrapper, 'Curitibanos, SC')).toBeUndefined();

    const map = wrapper.findComponent(MapStub);
    expect(map.props()).toMatchObject({
      apiKey: 'chave-navegador',
      center: { lat: -25.4284, lng: -49.2733 },
      radius: 1000,
      bounds: null,
      fitOnRender: true,
      heightClass: 'h-80',
    });

    await radiusInput(wrapper).setValue('2.5');
    expect(wrapper.findComponent(MapStub).props('radius')).toBe(2500);
  });

  it('confirma sugestão sem place_id sem consultar o detalhe e sem mapa quando não há coordenadas', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
      data: { payload: [{ text: 'Bairro Batel', label: 'Batel, Curitiba' }] },
    });

    await locationInput(wrapper).setValue('Bate');
    await waitLocationDebounce();
    await buttonWithText(wrapper, 'Bairro Batel').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getLocationDetails).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Batel, Curitiba');
    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
  });

  it('usa a área visível do mapa: sem raio no mapa, sem ajuste automático e sem expandir raio', async () => {
    const wrapper = await openFormWithoutHistory();
    await confirmCuritiba(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.AREA_TYPE', 'viewport');

    const map = wrapper.findComponent(MapStub);
    expect(map.props('radius')).toBe(0);
    expect(map.props('fitOnRender')).toBe(false);
    expect(map.props('bounds')).toBeNull();
    expect(autoExpandInput(wrapper).element.disabled).toBe(true);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_VIEWPORT_HINT');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_VIEWPORT_SHORT');

    const bounds = { north: 1, south: 0, east: 1, west: 0 };
    map.vm.$emit('viewportChange', { center: { lat: 0.5, lng: 0.5 }, bounds });
    await flushPromises();
    expect(wrapper.findComponent(MapStub).props('bounds')).toEqual(bounds);
  });

  it('só libera a busca com termo e local confirmado, e digitar de novo desconfirma o local', async () => {
    const wrapper = await openFormWithoutHistory();

    await queryInput(wrapper).setValue('padaria');
    expect(submitButton(wrapper).element.disabled).toBe(true);

    await confirmCuritiba(wrapper);
    expect(submitButton(wrapper).element.disabled).toBe(false);

    await locationInput(wrapper).setValue('Curitiba, P');
    expect(submitButton(wrapper).element.disabled).toBe(true);
    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
  });

  // Mudou de propósito (frente B): os filtros estão numa gaveta com rascunho, a
  // contagem só muda depois de "Aplicar" e "aberto agora" virou caixa "sim".
  it('mostra o total de filtros avançados aplicados', async () => {
    const wrapper = await openFormWithoutHistory();
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.ACTIVE_FILTERS');

    await openFormFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'above');
    await choose(wrapper, `${DRAWER}.RATING.VALUE`, 4);
    expect(
      ['HAS_SITE', 'HAS_PHONE', 'HAS_PHOTOS'].map(field =>
        choiceSelect(wrapper, `PROSPECTING.SEARCH.FIELDS.${field}`)
          .props('options')
          .map(option => option.value)
      )
    ).toEqual(Array(3).fill(['', 'yes', 'no']));
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.ACTIVE_FILTERS');

    await applyFilters(wrapper);

    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.ACTIVE_FILTERS');
  });

  it('envia o payload exato da busca por raio', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: bakerySearch(), leads: [sunLead()] } },
    });

    await queryInput(wrapper).setValue('  padaria artesanal  ');
    await confirmCuritiba(wrapper);
    await radiusInput(wrapper).setValue('2.5');
    await limitInput(wrapper).setValue('30');
    await autoExpandInput(wrapper).setValue(false);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE', 'gbp');
    await openFormFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'yes');
    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'above');
    await choose(wrapper, `${DRAWER}.RATING.VALUE`, 4);
    await rankInput(wrapper, 'MAX_ARIA').setValue('10');
    await applyFilters(wrapper);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith({
      query: 'padaria artesanal',
      location: 'Curitiba, PR, Brasil',
      radius: 2500,
      area_type: 'radius',
      area_config: {
        center: { lat: -25.4284, lng: -49.2733 },
        label: 'Curitiba, PR, Brasil',
        place_id: 'place-cwb',
        radius: 2500,
      },
      requested_limit: 30,
      crm_pipeline_id: 3,
      crm_stage_id: 31,
      metadata: {
        location_place_id: 'place-cwb',
        location_latitude: '-25.4284',
        location_longitude: '-49.2733',
        location_label: 'Curitiba, PR, Brasil',
        filters: { auto_expand_radius: false },
        decision_maker_type: 'owner',
        advanced_filters: {
          has_website: 'yes',
          has_phone: '',
          has_photos: '',
          open_now: '',
          has_opening_hours: '',
          rating_min: 4,
          rating_max: '',
          reviews_min: '',
          outside_top: '',
          search_rank_max: 10,
        },
        sort_key: 'priority_desc',
        score_mode: 'gbp',
        preset_id: null,
        scoring_profile_id: 9,
      },
    });
  });

  // LOCAL-42 (#682, E6): arrastar a prévia mudava o centro da busca e o
  // círculo ficava no local. Como no Orth (BuscaClient.tsx, mapCenter), no
  // modo raio o centro é o do local escolhido, o mesmo do círculo.
  it('no modo raio, arrastar a prévia não tira o centro da busca do círculo', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: bakerySearch(), leads: [] } },
    });

    await queryInput(wrapper).setValue('padaria');
    await confirmCuritiba(wrapper);
    const map = wrapper.findComponent(MapStub);
    map.vm.$emit('viewportChange', {
      center: { lat: -25.3, lng: -49.1 },
      bounds: { north: -25.2, south: -25.4, east: -49.0, west: -49.2 },
    });
    await flushPromises();
    const circleCenter = wrapper.findComponent(MapStub).props('center');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    const [payload] = AutonomiaProspectingAPI.createSearch.mock.calls[0];
    expect(circleCenter).toEqual({ lat: -25.4284, lng: -49.2733 });
    expect(payload.area_config.center).toEqual(circleCenter);
  });

  it('envia o payload exato da busca por área visível', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: bakerySearch(), leads: [] } },
    });
    const bounds = { north: -25.3, south: -25.5, east: -49.1, west: -49.4 };

    await queryInput(wrapper).setValue('academia');
    await confirmCuritiba(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.AREA_TYPE', 'viewport');
    const viewport = { center: { lat: -25.4, lng: -49.25 }, bounds };
    wrapper.findComponent(MapStub).vm.$emit('viewportChange', viewport);
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    const [payload] = AutonomiaProspectingAPI.createSearch.mock.calls[0];
    expect(payload.area_type).toBe('viewport');
    expect(payload.radius).toBe(1000);
    expect(payload.area_config).toEqual({
      center: { lat: -25.4, lng: -49.25 },
      label: 'Curitiba, PR, Brasil',
      place_id: 'place-cwb',
      radius: 1000,
      bounds,
    });
    expect(payload.metadata.score_mode).toBe('general');
    expect(payload.metadata.filters).toEqual({ auto_expand_radius: true });
  });

  it('depois de criar recarrega o histórico, fecha o formulário e mostra os leads da busca nova', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: bakerySearch(), leads: [sunLead()] } },
    });
    AutonomiaProspectingAPI.getSearches.mockResolvedValue({
      data: {
        payload: [bakerySearch()],
        meta: { page: 1, per_page: 20, total_count: 1, has_more: false },
      },
    });

    await queryInput(wrapper).setValue('padaria');
    await confirmCuritiba(wrapper);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getSearches).toHaveBeenLastCalledWith({
      page: 1,
      per_page: 20,
    });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_FOR');
    expect(leadNames(wrapper)).toEqual(['Padaria Sol']);
  });

  // O Google falhou numa página seguinte (#678): a busca vem com o que chegou
  // e a tela avisa que pode estar incompleta. Busca inteira não avisa nada.
  it('avisa quando a busca veio parcial e fica calada na busca completa', async () => {
    const submitWith = async summary => {
      useAlert.mockClear();
      const wrapper = await openFormWithoutHistory();
      AutonomiaProspectingAPI.createSearch.mockResolvedValue({
        data: {
          payload: { search: bakerySearch({ summary }), leads: [sunLead()] },
        },
      });
      await queryInput(wrapper).setValue('padaria');
      await confirmCuritiba(wrapper);
      await wrapper.find('form').trigger('submit');
      await flushPromises();
      return wrapper;
    };

    const partial = await submitWith({ partial_results: true });
    expect(leadNames(partial)).toEqual(['Padaria Sol']);
    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.SEARCH.PARTIAL_RESULTS');
    partial.unmount();

    await submitWith({ partial_results: false });
    expect(useAlert).not.toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.PARTIAL_RESULTS'
    );
  });

  it('avisa o erro da API e mantém o formulário aberto quando a busca falha', async () => {
    const wrapper = await openFormWithoutHistory();
    AutonomiaProspectingAPI.createSearch.mockRejectedValueOnce({
      response: { data: { error: 'Limite diário atingido' } },
    });
    AutonomiaProspectingAPI.createSearch.mockRejectedValueOnce(new Error('x'));

    await queryInput(wrapper).setValue('padaria');
    await confirmCuritiba(wrapper);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Limite diário atingido');
    expect(wrapper.find('form').exists()).toBe(true);
    expect(submitButton(wrapper).element.disabled).toBe(false);

    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(useAlert).toHaveBeenLastCalledWith(
      'PROSPECTING.ERRORS.CREATE_SEARCH'
    );
  });

  it('ao abrir zera os filtros e ao voltar restaura os filtros e a ordem da busca aberta', async () => {
    const search = bakerySearch({
      advanced_filters: { has_phone: 'yes' },
      sort_key: 'rating_desc',
    });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });

    await toggleNewSearch(wrapper);
    await openFormFilters(wrapper);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE').props(
        'modelValue'
      )
    ).toBe('');

    await toggleNewSearch(wrapper);
    await openResultFilters(wrapper);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE').props(
        'modelValue'
      )
    ).toBe('yes');
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SORT').props(
        'modelValue'
      )
    ).toBe('rating');
  });
});
