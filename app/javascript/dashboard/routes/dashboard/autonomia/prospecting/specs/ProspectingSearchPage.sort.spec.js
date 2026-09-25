// Ordenação da busca aberta (#678, E2 frente A): escolhe o campo e inverte a
// direção, como no Orth; Distância e Google começam do mais perto e da 1ª
// posição. A chave continua "<campo>_<direção>", a mesma sort_key que a busca
// já gravava.
import { flushPromises } from '@vue/test-utils';
import {
  bakerySearch,
  choiceSelect,
  choose,
  hotBreadLead,
  leadNames,
  moonLead,
  mountSearchPage,
  openResultFilters,
  sunLead,
  toggleNewSearch,
} from './support/searchPageHarness';
import { submitMinimalSearch } from './support/searchFormHelpers';

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

const SORT = 'PROSPECTING.SEARCH.FIELDS.SORT';
const sortField = wrapper => choiceSelect(wrapper, SORT);
const directionButton = wrapper => wrapper.find('[data-test="sort-direction"]');

const invertDirection = async wrapper => {
  await directionButton(wrapper).trigger('click');
  await flushPromises();
};

const mountWithSearch = async search =>
  mountSearchPage({
    searches: [search],
    payloads: {
      11: { search, leads: [sunLead(), hotBreadLead(), moonLead()] },
    },
  });

describe('ProspectingSearchPage · ordenação', () => {
  it('oferece os campos do Orth e os do chat2you, com Prioridade marcada', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    expect(sortField(wrapper).props('modelValue')).toBe('priority');
    expect(
      sortField(wrapper)
        .props('options')
        .map(option => option.value)
    ).toEqual([
      'priority',
      'score',
      'rating',
      'reviews',
      'distance',
      'google_rank',
      'created',
      'name',
    ]);
    expect(directionButton(wrapper).attributes('aria-label')).toBe(
      'PROSPECTING.SEARCH.SORT.INVERT'
    );
  });

  it('Google começa da 1ª posição e o botão inverte para a última', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, SORT, 'google_rank');
    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Pão Quente',
      'Confeitaria Lua',
    ]);

    await invertDirection(wrapper);
    expect(leadNames(wrapper)).toEqual([
      'Confeitaria Lua',
      'Pão Quente',
      'Padaria Sol',
    ]);
    expect(sortField(wrapper).props('modelValue')).toBe('google_rank');
  });

  it('Distância começa do mais perto do centro da busca e deixa sem coordenada no fim', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, SORT, 'distance');
    expect(leadNames(wrapper)).toEqual([
      'Confeitaria Lua',
      'Padaria Sol',
      'Pão Quente',
    ]);

    await invertDirection(wrapper);
    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Confeitaria Lua',
      'Pão Quente',
    ]);
  });

  it('sem centro na busca não oferece Distância', async () => {
    const wrapper = await mountWithSearch(
      bakerySearch({ area_config: {}, location_latitude: null })
    );
    await openResultFilters(wrapper);

    expect(
      sortField(wrapper)
        .props('options')
        .map(option => option.value)
    ).not.toContain('distance');
  });

  it('prioridade invertida põe a última posição primeiro', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await invertDirection(wrapper);

    expect(leadNames(wrapper)).toEqual([
      'Confeitaria Lua',
      'Pão Quente',
      'Padaria Sol',
    ]);
  });

  it('trocar o campo volta para a direção que põe o melhor primeiro', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);
    await choose(wrapper, SORT, 'score');
    await invertDirection(wrapper);

    await choose(wrapper, SORT, 'rating');

    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Confeitaria Lua',
      'Pão Quente',
    ]);
  });

  it('reabre a busca com a ordem salva no formato antigo', async () => {
    const wrapper = await mountWithSearch(
      bakerySearch({ sort_key: 'created_asc' })
    );
    await openResultFilters(wrapper);

    expect(sortField(wrapper).props('modelValue')).toBe('created');
    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Confeitaria Lua',
      'Pão Quente',
    ]);
  });

  it('a nova busca leva a ordem escolhida com a direção', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);
    await choose(wrapper, SORT, 'google_rank');
    await invertDirection(wrapper);
    await toggleNewSearch(wrapper);

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata.sort_key).toBe('google_rank_desc');
  });
});
