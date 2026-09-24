// Frente de modo e jogadas (#677): selo do modo no topo, grade de jogadas no
// formulário, jogada no pedido, no histórico e ao reabrir uma busca.
import { flushPromises } from '@vue/test-utils';
import {
  bakerySearch,
  choose,
  defaultPayloads,
  gymSearch,
  historyCards,
  leadNames,
  mountSearchPage,
  openResultFilters,
  settingsFixture,
  toggleNewSearch,
} from './support/searchPageHarness';
import { submitMinimalSearch } from './support/searchFormHelpers';
import {
  applyFilters,
  openFormFilters,
  reviewsMinInput,
} from './support/filtersHelpers';

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

const PRESET = key => `PROSPECTING.SEARCH.PRESETS.ITEMS.${key}.NAME`;
const NO_PRESET = 'PROSPECTING.SEARCH.PRESETS.NONE_NAME';
const SCORE_MODE = 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE';

const modeBadge = wrapper => wrapper.find('[data-test="search-mode-badge"]');
const openSearchPresetChip = wrapper =>
  wrapper.find('header [data-test="search-preset-chip"]');
const presetButtons = wrapper =>
  wrapper.findAll('[data-test="search-preset-grid"] button');
const presetButton = (wrapper, text) =>
  presetButtons(wrapper).find(button => button.text().includes(text));
const presetNames = wrapper =>
  presetButtons(wrapper).map(button => button.find('strong').text());
const pressedPreset = wrapper =>
  presetButtons(wrapper)
    .filter(button => button.attributes('aria-pressed') === 'true')
    .map(button => button.find('strong').text());

const ACTIVE_FILTERS = 'PROSPECTING.SEARCH.ACTIVE_FILTERS';

// Os filtros só mudam depois de Aplicar na gaveta (frente B).
const applyReviewsMin = async (wrapper, value) => {
  await reviewsMinInput(wrapper).setValue(value);
  await applyFilters(wrapper);
};

const setFormReviewsMin = async (wrapper, value) => {
  await openFormFilters(wrapper);
  await applyReviewsMin(wrapper, value);
};

const choosePreset = async (wrapper, key) => {
  await presetButton(wrapper, PRESET(key)).trigger('click');
  await flushPromises();
};

const openForm = async (options = {}) => {
  const wrapper = await mountSearchPage({ searches: [], ...options });
  await toggleNewSearch(wrapper);
  return wrapper;
};

describe('Busca · selo do modo', () => {
  it('sem busca aberta mostra o modo da conta, verde no Geral', async () => {
    const wrapper = await mountSearchPage({ searches: [] });

    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GENERAL'
    );
    expect(modeBadge(wrapper).classes().join(' ')).toContain('n-teal');
    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GENERAL_TOOLTIP'
    );
  });

  it('ao reabrir uma busca mostra o modo daquela busca, âmbar no GMN', async () => {
    const wrapper = await mountSearchPage({
      searches: [bakerySearch({ score_mode: 'gbp' })],
      payloads: {
        11: { search: bakerySearch({ score_mode: 'gbp' }), leads: [] },
      },
    });

    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GBP'
    );
    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GBP_TOOLTIP'
    );
    expect(modeBadge(wrapper).classes().join(' ')).toContain('n-amber');
  });

  it('no formulário segue o modo escolhido para a nova busca', async () => {
    const wrapper = await openForm();
    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GENERAL'
    );

    await choose(wrapper, SCORE_MODE, 'gbp');

    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GBP'
    );
  });
});

describe('Busca · grade de jogadas', () => {
  it('mostra as três jogadas do modo e o cartão Sem jogada marcado', async () => {
    const wrapper = await openForm();

    expect(presetNames(wrapper)).toEqual([
      PRESET('PROVA_SOCIAL'),
      PRESET('MERCADO_MADURO'),
      PRESET('PRESENCA_DIGITAL'),
      NO_PRESET,
    ]);
    expect(pressedPreset(wrapper)).toEqual([NO_PRESET]);

    await choose(wrapper, SCORE_MODE, 'gbp');

    expect(presetNames(wrapper)).toEqual([
      PRESET('VENDER_SITE'),
      PRESET('GESTAO_REVIEWS'),
      PRESET('OTIMIZACAO_GBP'),
      NO_PRESET,
    ]);
  });

  it('escolher jogada preenche os filtros dela e vai no pedido', async () => {
    const wrapper = await openForm();

    await choosePreset(wrapper, 'MERCADO_MADURO');
    expect(pressedPreset(wrapper)).toEqual([PRESET('MERCADO_MADURO')]);
    await openFormFilters(wrapper);
    expect(reviewsMinInput(wrapper).element.value).toBe('20');
    await applyFilters(wrapper);
    expect(pressedPreset(wrapper)).toEqual([PRESET('MERCADO_MADURO')]);

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata.preset_id).toBe('mercado-maduro');
    expect(payload.metadata.advanced_filters).toMatchObject({
      rating_min: 4,
      reviews_min: 20,
      has_website: '',
    });
  });

  it('editar um filtro até divergir desmarca a jogada e mantém os filtros', async () => {
    const wrapper = await openForm();
    await choosePreset(wrapper, 'MERCADO_MADURO');

    await setFormReviewsMin(wrapper, '20');
    expect(pressedPreset(wrapper)).toEqual([PRESET('MERCADO_MADURO')]);

    await setFormReviewsMin(wrapper, '50');
    expect(pressedPreset(wrapper)).toEqual([NO_PRESET]);

    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.preset_id).toBeNull();
    expect(payload.metadata.advanced_filters).toMatchObject({
      rating_min: 4,
      reviews_min: 50,
    });
  });

  it('trocar o modo com jogada de outro modo limpa a jogada', async () => {
    const wrapper = await openForm();
    await choosePreset(wrapper, 'PROVA_SOCIAL');

    await choose(wrapper, SCORE_MODE, 'gbp');

    expect(pressedPreset(wrapper)).toEqual([NO_PRESET]);
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.preset_id).toBeNull();
    expect(payload.metadata.score_mode).toBe('gbp');
  });

  it('clicar de novo na jogada ou em Sem jogada limpa a jogada e os filtros dela', async () => {
    const wrapper = await openForm();
    await choosePreset(wrapper, 'PROVA_SOCIAL');
    expect(wrapper.text()).toContain(ACTIVE_FILTERS);

    await choosePreset(wrapper, 'PROVA_SOCIAL');
    expect(pressedPreset(wrapper)).toEqual([NO_PRESET]);
    expect(wrapper.text()).not.toContain(ACTIVE_FILTERS);

    await choosePreset(wrapper, 'PRESENCA_DIGITAL');
    await presetButton(wrapper, NO_PRESET).trigger('click');
    await flushPromises();

    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.preset_id).toBeNull();
    expect(payload.metadata.advanced_filters).toMatchObject({
      has_website: '',
      has_phone: '',
    });
  });

  it('Sem jogada sem jogada marcada não apaga filtro posto à mão', async () => {
    const wrapper = await openForm();
    await setFormReviewsMin(wrapper, '7');

    await presetButton(wrapper, NO_PRESET).trigger('click');
    await flushPromises();

    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.advanced_filters.reviews_min).toBe(7);
  });

  it('escolher jogada não mexe nos resultados abertos', async () => {
    const wrapper = await mountSearchPage();
    const before = leadNames(wrapper);
    expect(before).toHaveLength(3);

    await toggleNewSearch(wrapper);
    await choose(wrapper, SCORE_MODE, 'gbp');
    await choosePreset(wrapper, 'VENDER_SITE');
    await toggleNewSearch(wrapper);

    expect(leadNames(wrapper)).toEqual(before);
  });
});

describe('Busca · jogada no histórico e ao reabrir', () => {
  const presetPayloads = () => ({
    ...defaultPayloads(),
    11: {
      ...defaultPayloads()[11],
      search: bakerySearch({
        score_mode: 'general',
        preset_id: 'prova-social',
        advanced_filters: { rating_min: 4.2 },
      }),
    },
  });

  it('mostra o selo da jogada só na busca que tem jogada', async () => {
    const wrapper = await mountSearchPage({
      searches: [bakerySearch({ preset_id: 'prova-social' }), gymSearch()],
    });

    const [withPreset, withoutPreset] = historyCards(wrapper);
    expect(
      withPreset.find('[data-test="search-preset-chip"]').text()
    ).toContain(PRESET('PROVA_SOCIAL'));
    expect(
      withoutPreset.find('[data-test="search-preset-chip"]').exists()
    ).toBe(false);
  });

  it('reabrir restaura a jogada da busca no topo', async () => {
    const wrapper = await mountSearchPage({ payloads: presetPayloads() });

    expect(openSearchPresetChip(wrapper).text()).toContain(
      PRESET('PROVA_SOCIAL')
    );
  });

  it('refinar os resultados até divergir desmarca a jogada da busca aberta', async () => {
    const wrapper = await mountSearchPage({ payloads: presetPayloads() });
    await openResultFilters(wrapper);

    await applyReviewsMin(wrapper, '3');

    expect(openSearchPresetChip(wrapper).exists()).toBe(false);
  });

  it('abrir busca sem jogada não mostra selo de jogada no topo', async () => {
    const wrapper = await mountSearchPage();

    expect(openSearchPresetChip(wrapper).exists()).toBe(false);
  });

  it('a jogada da busca vem no payload restaurado mesmo com modo diferente da conta', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({ search_score_mode: 'gbp' }),
      payloads: presetPayloads(),
    });

    expect(modeBadge(wrapper).text()).toContain(
      'PROSPECTING.SEARCH.MODE_BADGE.GENERAL'
    );
    expect(openSearchPresetChip(wrapper).text()).toContain(
      PRESET('PROVA_SOCIAL')
    );
  });
});
