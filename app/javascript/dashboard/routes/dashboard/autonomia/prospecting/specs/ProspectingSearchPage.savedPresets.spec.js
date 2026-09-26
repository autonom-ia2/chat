// Jogadas salvas (#732; MODO-25, FILTRO-27, PLAT-17): "Salvar como jogada" na
// gaveta de filtros grava os filtros da conta, e a jogada salva aparece na
// grade ao lado das prontas, no modo em que foi salva. Só quem gerencia a
// prospecção salva; quem só vê usa as jogadas salvas.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithText,
  gymSearch,
  historyCards,
  mountSearchPage,
  openResultFilters,
  settingsFixture,
  toggleNewSearch,
} from './support/searchPageHarness';
import { submitMinimalSearch } from './support/searchFormHelpers';
import {
  DRAWER,
  filtersPanel,
  openFormFilters,
  reviewsMinInput,
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

const SAVE = 'PROSPECTING.SEARCH.SAVED_PRESETS';
const NO_PRESET = 'PROSPECTING.SEARCH.PRESETS.NONE_NAME';
const TAG = key => `${SAVE}.TAGS.${key}`;

const savedPayload = (extra = {}) => ({
  id: 7,
  preset_id: 'saved-7',
  name: 'Sem site com telefone',
  score_mode: 'general',
  filters: { has_website: 'no', has_phone: 'yes' },
  ...extra,
});

const presetButtons = wrapper =>
  wrapper.findAll('[data-test="search-preset-grid"] button');
const presetNames = wrapper =>
  presetButtons(wrapper).map(button => button.find('strong').text());
const presetButton = (wrapper, text) =>
  presetButtons(wrapper).find(button => button.text().includes(text));
const pressedPreset = wrapper =>
  presetButtons(wrapper)
    .filter(button => button.attributes('aria-pressed') === 'true')
    .map(button => button.find('strong').text());
const saveModal = wrapper => wrapper.find('[data-test="save-preset-modal"]');
const saveButtonInPanel = wrapper =>
  buttonWithText(filtersPanel(wrapper), `${SAVE}.SAVE_AS`);

const openForm = async (settings = settingsFixture()) => {
  const wrapper = await mountSearchPage({ searches: [], settings });
  await toggleNewSearch(wrapper);
  return wrapper;
};

const openSaveModalWithReviews = async (wrapper, value = '12') => {
  await openFormFilters(wrapper);
  await reviewsMinInput(wrapper).setValue(value);
  await saveButtonInPanel(wrapper).trigger('click');
  await flushPromises();
};

beforeEach(() => {
  permission.canManage = true;
  vi.clearAllMocks();
});

describe('Busca · jogadas salvas na grade', () => {
  it('mostra a jogada salva do modo depois das prontas, com o resumo dos filtros', async () => {
    const wrapper = await openForm(
      settingsFixture({
        saved_presets: [
          savedPayload(),
          savedPayload({
            id: 8,
            preset_id: 'saved-8',
            name: 'Do outro modo',
            score_mode: 'gbp',
          }),
        ],
      })
    );

    expect(presetNames(wrapper)).toEqual([
      'PROSPECTING.SEARCH.PRESETS.ITEMS.PROVA_SOCIAL.NAME',
      'PROSPECTING.SEARCH.PRESETS.ITEMS.MERCADO_MADURO.NAME',
      'PROSPECTING.SEARCH.PRESETS.ITEMS.PRESENCA_DIGITAL.NAME',
      'Sem site com telefone',
      NO_PRESET,
    ]);
    const card = presetButton(wrapper, 'Sem site com telefone');
    expect(card.text()).toContain(TAG('HAS_WEBSITE_NO'));
    expect(card.text()).toContain(TAG('HAS_PHONE_YES'));
  });

  it('escolher a jogada salva aplica os filtros dela e vai no pedido', async () => {
    const wrapper = await openForm(
      settingsFixture({ saved_presets: [savedPayload()] })
    );

    await presetButton(wrapper, 'Sem site com telefone').trigger('click');
    await flushPromises();

    expect(pressedPreset(wrapper)).toEqual(['Sem site com telefone']);
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.preset_id).toBe('saved-7');
    expect(payload.metadata.advanced_filters).toMatchObject({
      has_website: 'no',
      has_phone: 'yes',
    });
  });

  it('o histórico mostra o selo da jogada salva pelo nome', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({ saved_presets: [savedPayload()] }),
      searches: [bakerySearch({ preset_id: 'saved-7' }), gymSearch()],
    });

    expect(
      historyCards(wrapper)[0].find('[data-test="search-preset-chip"]').text()
    ).toContain('Sem site com telefone');
  });
});

describe('Busca · Salvar como jogada', () => {
  it('grava os filtros do rascunho com o nome e o modo, e a jogada nova fica marcada', async () => {
    const wrapper = await openForm();
    AutonomiaProspectingAPI.createSavedPreset.mockResolvedValue({
      data: {
        payload: savedPayload({
          id: 9,
          preset_id: 'saved-9',
          name: 'Muitas avaliações',
          filters: { reviews_min: 12 },
        }),
      },
    });

    await openSaveModalWithReviews(wrapper);
    expect(saveModal(wrapper).text()).toContain(TAG('REVIEWS_MIN'));
    await saveModal(wrapper).find('input').setValue('  Muitas avaliações ');
    await buttonWithText(saveModal(wrapper), `${SAVE}.SAVE`).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSavedPreset).toHaveBeenCalledWith({
      name: 'Muitas avaliações',
      score_mode: 'general',
      filters: expect.objectContaining({ reviews_min: 12, has_website: '' }),
    });
    expect(saveModal(wrapper).exists()).toBe(false);
    expect(pressedPreset(wrapper)).toEqual(['Muitas avaliações']);
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.preset_id).toBe('saved-9');
    expect(payload.metadata.advanced_filters.reviews_min).toBe(12);
  });

  it('sem nome não salva', async () => {
    const wrapper = await openForm();
    await openSaveModalWithReviews(wrapper);

    expect(
      buttonWithText(saveModal(wrapper), `${SAVE}.SAVE`).attributes('disabled')
    ).toBeDefined();
  });

  it('recusa do servidor aparece na janela, que continua aberta', async () => {
    const wrapper = await openForm();
    AutonomiaProspectingAPI.createSavedPreset.mockRejectedValue({
      response: { data: { error: 'Já existe uma jogada com esse nome.' } },
    });

    await openSaveModalWithReviews(wrapper);
    await saveModal(wrapper).find('input').setValue('Repetida');
    await buttonWithText(saveModal(wrapper), `${SAVE}.SAVE`).trigger('click');
    await flushPromises();

    expect(saveModal(wrapper).find('[role="alert"]').text()).toBe(
      'Já existe uma jogada com esse nome.'
    );
    expect(pressedPreset(wrapper)).toEqual([NO_PRESET]);
  });

  it('sem filtro nenhum o botão fica desligado', async () => {
    const wrapper = await openForm();
    await openFormFilters(wrapper);

    expect(saveButtonInPanel(wrapper).attributes('disabled')).toBeDefined();
    expect(filtersPanel(wrapper).text()).toContain(`${DRAWER}.APPLY`);
  });

  // Quem só vê não abre nova busca; no refino da busca aberta ninguém salva, e
  // a jogada salva aparece pelo nome no selo da busca.
  it('quem só vê a prospecção não tem o botão, mas vê a jogada salva pelo nome', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage({
      settings: settingsFixture({ saved_presets: [savedPayload()] }),
      searches: [bakerySearch({ preset_id: 'saved-7' })],
    });
    await openResultFilters(wrapper);

    expect(filtersPanel(wrapper).exists()).toBe(true);
    expect(saveButtonInPanel(wrapper)).toBeUndefined();
    expect(
      historyCards(wrapper)[0].find('[data-test="search-preset-chip"]').text()
    ).toContain('Sem site com telefone');
  });
});
