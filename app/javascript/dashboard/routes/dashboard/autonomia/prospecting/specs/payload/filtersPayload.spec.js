// Pedaço do pedido da busca que pertence à frente de filtros e ordenação
// (#677, E1): advanced_filters e sort_key no metadata.
import { flushPromises } from '@vue/test-utils';
import {
  bakerySearch,
  choose,
  mountSearchPage,
  sunLead,
  toggleNewSearch,
} from '../support/searchPageHarness';
import {
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

const EMPTY_ADVANCED_FILTERS = {
  has_website: '',
  has_phone: '',
  has_photos: '',
  open_now: '',
  rating_min: '',
  rating_max: '',
  reviews_min: '',
  search_rank_max: '',
};

describe('Pedido da busca · frente de filtros e ordenação', () => {
  it('manda os filtros avançados escolhidos no formulário', async () => {
    const wrapper = await openNewSearchForm();
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.OPEN_NOW', 'no');
    await flushPromises();

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata).toMatchObject({
      advanced_filters: { ...EMPTY_ADVANCED_FILTERS, open_now: 'no' },
      sort_key: 'priority_desc',
    });
  });

  it('nova busca zera os filtros mas herda a ordenação da busca que estava aberta', async () => {
    const search = bakerySearch({
      advanced_filters: { has_phone: 'yes', rating_min: 4 },
      sort_key: 'rating_desc',
    });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });
    await toggleNewSearch(wrapper);

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata.sort_key).toBe('rating_desc');
    expect(payload.metadata.advanced_filters).toEqual(EMPTY_ADVANCED_FILTERS);
  });
});
