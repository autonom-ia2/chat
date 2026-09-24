// Limites da gaveta de filtros do formulário (#677): a faixa de posição não
// começa depois do que o Google devolve, e a nota que vem da jogada aparece no
// seletor de estrelas mesmo fora dos passos de meia estrela.
import {
  choiceSelect,
  choose,
  settingsFixture,
} from './support/searchPageHarness';
import {
  openNewSearchForm,
  submitMinimalSearch,
} from './support/searchFormHelpers';
import {
  DRAWER,
  applyFilters,
  filtersPanel,
  openFormFilters,
  rankInput,
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

const quantityInput = wrapper => wrapper.find('input[type="number"][max="60"]');

const setQuantityAndOpenFilters = async (wrapper, quantity) => {
  await quantityInput(wrapper).setValue(String(quantity));
  await openFormFilters(wrapper);
};

const dragMinRankTo = async (wrapper, value) => {
  await rankInput(wrapper, 'MIN_ARIA').setValue(String(value));
};

describe('Busca · faixa de posição que o Google alcança', () => {
  it('com Quantidade 10 a faixa começa no máximo em 10 e o pedido corta 9', async () => {
    const wrapper = await openNewSearchForm();
    await setQuantityAndOpenFilters(wrapper, 10);

    await dragMinRankTo(wrapper, 21);

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('10');
    expect(filtersPanel(wrapper).text()).toContain(`${DRAWER}.RANK.REACH`);
    await applyFilters(wrapper);
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.advanced_filters.outside_top).toBe(9);
  });

  it('com Quantidade 60 no Google a faixa começa no máximo em 20', async () => {
    const wrapper = await openNewSearchForm();
    await setQuantityAndOpenFilters(wrapper, 60);

    await dragMinRankTo(wrapper, 30);

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('20');
  });

  it('no provider fictício o teto é a própria Quantidade', async () => {
    const wrapper = await openNewSearchForm({
      settings: settingsFixture({ mock_provider: true }),
    });
    await setQuantityAndOpenFilters(wrapper, 30);

    await dragMinRankTo(wrapper, 35);

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('30');
  });
});

describe('Busca · nota da jogada no seletor de estrelas', () => {
  const ratingValue = wrapper =>
    choiceSelect(wrapper, `${DRAWER}.RATING.VALUE`);
  const ratingOperator = wrapper =>
    choiceSelect(wrapper, `${DRAWER}.RATING.OPERATOR`);

  const choosePresetAndOpenFilters = async (wrapper, key) => {
    const button = wrapper
      .findAll('[data-test="search-preset-grid"] button')
      .find(item =>
        item.text().includes(`PROSPECTING.SEARCH.PRESETS.ITEMS.${key}.NAME`)
      );
    await button.trigger('click');
    await openFormFilters(wrapper);
  };

  it('Prova social mostra "acima de 4,2" com o valor entre as opções', async () => {
    const wrapper = await openNewSearchForm();
    await choosePresetAndOpenFilters(wrapper, 'PROVA_SOCIAL');

    expect(ratingOperator(wrapper).props('modelValue')).toBe('above');
    expect(ratingValue(wrapper).props('modelValue')).toBe(4.2);
    expect(
      ratingValue(wrapper)
        .props('options')
        .map(option => option.value)
    ).toContain(4.2);
  });

  it('Gestão de avaliações mostra "abaixo de 4,2" com o valor entre as opções', async () => {
    const wrapper = await openNewSearchForm();
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE', 'gbp');
    await choosePresetAndOpenFilters(wrapper, 'GESTAO_REVIEWS');

    expect(ratingOperator(wrapper).props('modelValue')).toBe('below');
    expect(ratingValue(wrapper).props('modelValue')).toBe(4.2);
    expect(
      ratingValue(wrapper)
        .props('options')
        .map(option => option.value)
    ).toContain(4.2);
  });
});
