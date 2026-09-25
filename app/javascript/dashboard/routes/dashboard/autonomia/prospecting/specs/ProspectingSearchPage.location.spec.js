// Frente de local (#677, E1 frente C): tipo de decisor no bloco de quantidade e
// erro do Google visível nas sugestões e no detalhe do local, que antes
// falhavam calados.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  buttonWithText,
  choiceSelect,
  toggleNewSearch,
  waitLocationDebounce,
} from './support/searchPageHarness';
import { locationInput, openNewSearchForm } from './support/searchFormHelpers';

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

const DECISION_MAKER = 'PROSPECTING.DECISION_MAKER.LABEL';
const GOOGLE_ERROR = 'A busca no Google está indisponível no momento.';

const typeLocation = async (wrapper, text = 'Curi') => {
  await locationInput(wrapper).setValue(text);
  await waitLocationDebounce();
};

describe('Busca · tipo de decisor', () => {
  it('oferece os 11 perfis do Orth e só o Proprietário é selecionável', async () => {
    const wrapper = await openNewSearchForm();

    const choice = choiceSelect(wrapper, DECISION_MAKER);
    const options = choice.props('options');

    expect(choice.props('modelValue')).toBe('owner');
    expect(options.map(option => option.value)).toEqual([
      'owner',
      'ceo',
      'commercial',
      'financial',
      'marketing',
      'hr',
      'operations',
      'technology',
      'legal',
      'compliance',
      'risk',
    ]);
    expect(options.filter(option => !option.disabled)).toEqual([
      {
        value: 'owner',
        label: 'PROSPECTING.DECISION_MAKER.TYPES.OWNER',
        disabled: false,
      },
    ]);
    expect(
      options.filter(option => option.disabled).map(option => option.label)
    ).toEqual(Array(10).fill('PROSPECTING.DECISION_MAKER.COMING_SOON'));
  });
});

describe('Busca · erro do Google no local', () => {
  it('mostra o erro das sugestões em vez de sumir com a lista', async () => {
    const wrapper = await openNewSearchForm();
    AutonomiaProspectingAPI.getLocationSuggestions.mockRejectedValue({
      response: { data: { error: GOOGLE_ERROR } },
    });

    await typeLocation(wrapper);

    const alert = wrapper.find('[role="alert"]');
    expect(alert.exists()).toBe(true);
    expect(alert.text()).toBe(GOOGLE_ERROR);
  });

  it('usa um texto nosso quando a falha não traz mensagem', async () => {
    const wrapper = await openNewSearchForm();
    AutonomiaProspectingAPI.getLocationSuggestions.mockRejectedValue(
      new Error('Network Error')
    );

    await typeLocation(wrapper);

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'PROSPECTING.LOCATION_ERRORS.SUGGESTIONS'
    );
  });

  it('mostra o erro do detalhe do local e não confirma o local', async () => {
    const wrapper = await openNewSearchForm();
    AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
      data: { payload: [{ text: 'Curitiba, PR', place_id: 'place-cwb' }] },
    });
    AutonomiaProspectingAPI.getLocationDetails.mockRejectedValue({
      response: { data: { error: GOOGLE_ERROR } },
    });

    await typeLocation(wrapper);
    await buttonWithText(wrapper, 'Curitiba, PR').trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(GOOGLE_ERROR);
    expect(wrapper.text()).not.toContain(
      'PROSPECTING.SEARCH.LOCATION_CONFIRMED'
    );
  });

  it('limpa o erro quando a pessoa digita de novo e a sugestão volta', async () => {
    const wrapper = await openNewSearchForm();
    AutonomiaProspectingAPI.getLocationSuggestions.mockRejectedValueOnce({
      response: { data: { error: GOOGLE_ERROR } },
    });
    await typeLocation(wrapper);
    AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
      data: { payload: [{ text: 'Curitiba, PR', place_id: 'place-cwb' }] },
    });

    await typeLocation(wrapper, 'Curit');

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(buttonWithText(wrapper, 'Curitiba, PR')).toBeTruthy();
  });

  it('nova busca esquece o erro do local', async () => {
    const wrapper = await openNewSearchForm();
    AutonomiaProspectingAPI.getLocationSuggestions.mockRejectedValue({
      response: { data: { error: GOOGLE_ERROR } },
    });
    await typeLocation(wrapper);

    await toggleNewSearch(wrapper);
    await toggleNewSearch(wrapper);

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
