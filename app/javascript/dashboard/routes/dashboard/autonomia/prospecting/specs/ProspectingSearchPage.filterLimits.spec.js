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

// Com a paginação (#678) o Google alcança até a 60ª posição em qualquer
// Quantidade, além do fim do controle (40): a faixa começa onde a pessoa
// quiser e não há mais aviso de alcance. Antes o teto era a Quantidade, até 20.
describe('Busca · faixa de posição que o Google alcança', () => {
  it('com Quantidade 10 a faixa começa depois da 10ª e o pedido corta até ela', async () => {
    const wrapper = await openNewSearchForm();
    await setQuantityAndOpenFilters(wrapper, 10);

    await dragMinRankTo(wrapper, 30);

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('30');
    expect(filtersPanel(wrapper).text()).not.toContain(`${DRAWER}.RANK.REACH`);
    await applyFilters(wrapper);
    expect(wrapper.find('[data-test="rank-reach-warning"]').exists()).toBe(
      false
    );
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.advanced_filters.outside_top).toBe(29);
  });

  it('no provider fictício vale a mesma faixa', async () => {
    const wrapper = await openNewSearchForm({
      settings: settingsFixture({ mock_provider: true }),
    });
    await setQuantityAndOpenFilters(wrapper, 5);

    await dragMinRankTo(wrapper, 35);

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('35');
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
