// Área desenhada na tela de busca (#678, E2 frente B): escolher círculo,
// retângulo ou polígono troca a prévia pelo mapa de desenho, a busca só sai com
// a área desenhada e o pedido leva o desenho em area_config. Resumo e histórico
// dizem "área desenhada" com o tipo.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import SearchAreaDrawMap from '../../components/search/SearchAreaDrawMap.vue';
import {
  MapStub,
  bakerySearch,
  choose,
  historyCards,
  mountSearchPage,
} from '../support/searchPageHarness';
import {
  LOCATION_DETAILS,
  confirmCuritiba,
  openNewSearchForm,
  queryInput,
} from '../support/searchFormHelpers';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('../support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('../support/searchPageMocks')).crmKanbanApiMock()
);

const AREA_TYPE = 'PROSPECTING.SEARCH.FIELDS.AREA_TYPE';
const PATH = [
  { lat: -25.5, lng: -49.3 },
  { lat: -25.5, lng: -49.2 },
  { lat: -25.4, lng: -49.25 },
];

const submitButton = wrapper => wrapper.find('button[type="submit"]');
const drawMap = wrapper => wrapper.findComponent(SearchAreaDrawMap);

const drawArea = async (wrapper, area) => {
  drawMap(wrapper).vm.$emit('update:modelValue', area);
  await flushPromises();
};

const formReadyToDraw = async areaType => {
  const wrapper = await openNewSearchForm();
  AutonomiaProspectingAPI.createSearch.mockResolvedValue({
    data: { payload: { search: bakerySearch(), leads: [] } },
  });
  await queryInput(wrapper).setValue('padaria');
  await confirmCuritiba(wrapper);
  await choose(wrapper, AREA_TYPE, areaType);
  return wrapper;
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  const { calls } = AutonomiaProspectingAPI.createSearch.mock;
  return calls[calls.length - 1][0];
};

describe('Área desenhada · tela de busca', () => {
  it('troca a prévia pelo mapa de desenho no local escolhido e só libera a busca com a área desenhada', async () => {
    const wrapper = await formReadyToDraw('polygon');

    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
    expect(drawMap(wrapper).props()).toMatchObject({
      apiKey: 'chave-navegador',
      center: { lat: -25.4284, lng: -49.2733 },
      shape: 'polygon',
      defaultRadius: 1000,
    });
    expect(submitButton(wrapper).element.disabled).toBe(true);

    await drawArea(wrapper, { type: 'polygon', config: { path: PATH } });

    expect(submitButton(wrapper).element.disabled).toBe(false);
  });

  it('manda o polígono em area_config, com o rótulo do local', async () => {
    const wrapper = await formReadyToDraw('polygon');
    await drawArea(wrapper, { type: 'polygon', config: { path: PATH } });

    const payload = await submit(wrapper);

    expect(payload.area_type).toBe('polygon');
    expect(payload.area_config).toEqual({
      path: PATH,
      label: LOCATION_DETAILS.label,
      place_id: LOCATION_DETAILS.place_id,
    });
  });

  it('manda o círculo com o raio desenhado, também no campo radius', async () => {
    const wrapper = await formReadyToDraw('circle');
    const center = { lat: -25.41, lng: -49.26 };
    await drawArea(wrapper, {
      type: 'circle',
      config: { center, radius: 3200 },
    });

    const payload = await submit(wrapper);

    expect(payload).toMatchObject({
      area_type: 'circle',
      radius: 3200,
      area_config: { center, radius: 3200, label: LOCATION_DETAILS.label },
    });
  });

  it('manda o retângulo com os limites desenhados', async () => {
    const wrapper = await formReadyToDraw('rectangle');
    const bounds = { north: -25.4, south: -25.5, east: -49.2, west: -49.3 };
    await drawArea(wrapper, { type: 'rectangle', config: { bounds } });

    const payload = await submit(wrapper);

    expect(payload.area_type).toBe('rectangle');
    expect(payload.area_config).toMatchObject({ bounds });
    expect(payload.area_config).not.toHaveProperty('center');
  });

  it('trocar o tipo de área esquece o desenho anterior', async () => {
    const wrapper = await formReadyToDraw('circle');
    await drawArea(wrapper, {
      type: 'circle',
      config: { center: { lat: -25.4, lng: -49.2 }, radius: 800 },
    });

    await choose(wrapper, AREA_TYPE, 'radius');
    await choose(wrapper, AREA_TYPE, 'circle');

    expect(drawMap(wrapper).props('modelValue')).toBeNull();
    expect(submitButton(wrapper).element.disabled).toBe(true);
  });

  it('o resumo diz área desenhada com o tipo e o raio do círculo desenhado', async () => {
    const wrapper = await formReadyToDraw('circle');
    await drawArea(wrapper, {
      type: 'circle',
      config: { center: { lat: -25.4, lng: -49.2 }, radius: 2500 },
    });

    const summary = wrapper.find('aside');
    expect(summary.text()).toContain(
      'PROSPECTING.SEARCH.AREA_DRAW.SHORT_CIRCLE'
    );
    expect(summary.text()).toContain('2.5');

    await choose(wrapper, AREA_TYPE, 'polygon');
    expect(wrapper.find('aside').text()).toContain(
      'PROSPECTING.SEARCH.AREA_DRAW.SHORT_POLYGON'
    );
  });

  it('o histórico diz área desenhada com o tipo', async () => {
    const polygonSearch = bakerySearch({
      id: 21,
      area_type: 'polygon',
      area_config: { path: PATH, center: { lat: -25.45, lng: -49.25 } },
    });
    const circleSearch = bakerySearch({ id: 22, area_type: 'circle' });
    const wrapper = await mountSearchPage({
      searches: [polygonSearch, circleSearch],
      payloads: {},
    });

    const [polygonCard, circleCard] = historyCards(wrapper);
    expect(polygonCard.find('p').text()).toBe(
      'Curitiba, PR · PROSPECTING.SEARCH.AREA_DRAW.SHORT_POLYGON'
    );
    expect(circleCard.find('p').text()).toBe(
      'Curitiba, PR · PROSPECTING.SEARCH.AREA_DRAW.SHORT_CIRCLE'
    );
  });
});
