// Pedaço do pedido da busca que pertence à frente de local, país e endereço
// (#677, E1): location, radius, area_type, area_config e location_* no metadata,
// e o tipo de decisor (decision_maker_type, Proprietário por padrão).
import {
  bakerySearch,
  choose,
  mountSearchPage,
  sunLead,
  toggleNewSearch,
} from '../support/searchPageHarness';
import {
  LOCATION_DETAILS,
  confirmCuritiba,
  locationInput,
  openNewSearchForm,
  submitMinimalSearch,
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

describe('Pedido da busca · frente de local', () => {
  it('manda o local confirmado, o raio em metros e a área padrão', async () => {
    const wrapper = await openNewSearchForm();

    const payload = await submitMinimalSearch(wrapper);

    expect(payload).toMatchObject({
      location: LOCATION_DETAILS.label,
      radius: 1000,
      area_type: 'radius',
      area_config: {
        center: { lat: -25.4284, lng: -49.2733 },
        label: LOCATION_DETAILS.label,
        place_id: LOCATION_DETAILS.place_id,
        radius: 1000,
      },
      metadata: {
        location_place_id: LOCATION_DETAILS.place_id,
        location_latitude: LOCATION_DETAILS.latitude,
        location_longitude: LOCATION_DETAILS.longitude,
        location_label: LOCATION_DETAILS.label,
        filters: { auto_expand_radius: false },
        decision_maker_type: 'owner',
      },
    });
    expect(payload.area_config).not.toHaveProperty('bounds');
  });

  it('nova busca volta a área para raio e esquece o local da busca anterior', async () => {
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });
    await toggleNewSearch(wrapper);
    await confirmCuritiba(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.AREA_TYPE', 'viewport');
    await toggleNewSearch(wrapper);
    await toggleNewSearch(wrapper);

    expect(locationInput(wrapper).element.value).toBe('');
    expect(wrapper.text()).not.toContain(
      'PROSPECTING.SEARCH.LOCATION_CONFIRMED'
    );
    expect(wrapper.find('button[type="submit"]').element.disabled).toBe(true);

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.area_type).toBe('radius');
    expect(payload.metadata.location_label).toBe(LOCATION_DETAILS.label);
  });
});
