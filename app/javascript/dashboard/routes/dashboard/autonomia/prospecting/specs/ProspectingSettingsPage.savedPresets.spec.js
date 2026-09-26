// Jogadas salvas nas Configurações da Prospecção (#732, MODO-26): a lista da
// conta, com editar (nome e filtros) e excluir. A tela é só de quem gerencia a
// prospecção (rota com prospecting_manage).
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import ProspectingSettingsPage from '../pages/ProspectingSettingsPage.vue';

vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    updateSettings: vi.fn(),
    updateSavedPreset: vi.fn(),
    deleteSavedPreset: vi.fn(),
  },
}));

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    getStages: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const PRESETS = 'PROSPECTING.SETTINGS.SAVED_PRESETS';
const TAG = key => `PROSPECTING.SEARCH.SAVED_PRESETS.TAGS.${key}`;

const savedPayload = (extra = {}) => ({
  id: 7,
  preset_id: 'saved-7',
  name: 'Sem site com telefone',
  score_mode: 'gbp',
  filters: { has_website: 'no', has_phone: 'yes' },
  ...extra,
});

const payloadBase = {
  id: 1,
  cache_ttl_seconds: 3600,
  scoring_mode: 'profile',
  scoring_profile_id: 1,
  scoring_profiles: [{ id: 1, name: 'Padrão', default: true, weights: {} }],
  active_scoring_weights: {},
  search_score_mode: 'gbp',
  usage: { daily_used: 0, monthly_used: 0 },
};

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().trim() === text);

const mountPage = async (savedPresets = [savedPayload()]) => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: { ...payloadBase, saved_presets: savedPresets } },
  });
  const wrapper = mount(ProspectingSettingsPage, {
    global: { stubs: { BaseSettingsHeader: true, ChoiceSelect: true } },
  });
  await flushPromises();
  await buttonWithText(wrapper, 'PROSPECTING.SETTINGS.TABS.PRESETS').trigger(
    'click'
  );
  return wrapper;
};

const presetRows = wrapper => wrapper.findAll('[data-test="saved-preset-row"]');
const editModal = wrapper =>
  wrapper.find('[data-test="saved-preset-edit-modal"]');

describe('Configurações · jogadas salvas', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lista as jogadas da conta com o modo e o resumo dos filtros', async () => {
    const wrapper = await mountPage();

    expect(presetRows(wrapper)).toHaveLength(1);
    const row = presetRows(wrapper)[0];
    expect(row.text()).toContain('Sem site com telefone');
    expect(row.text()).toContain('PROSPECTING.SEARCH.SCORE_MODES.GBP');
    expect(row.text()).toContain(TAG('HAS_WEBSITE_NO'));
    expect(row.text()).toContain(TAG('HAS_PHONE_YES'));
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SETTINGS.SAVE')
    ).toBeUndefined();
  });

  it('sem jogada salva explica onde salvar', async () => {
    const wrapper = await mountPage([]);

    expect(presetRows(wrapper)).toHaveLength(0);
    expect(wrapper.text()).toContain(`${PRESETS}.EMPTY`);
  });

  it('exclui depois de confirmar', async () => {
    AutonomiaProspectingAPI.deleteSavedPreset.mockResolvedValue({});
    const wrapper = await mountPage();

    await buttonWithText(presetRows(wrapper)[0], `${PRESETS}.DELETE`).trigger(
      'click'
    );
    expect(AutonomiaProspectingAPI.deleteSavedPreset).not.toHaveBeenCalled();
    await buttonWithText(
      presetRows(wrapper)[0],
      `${PRESETS}.CONFIRM_DELETE`
    ).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.deleteSavedPreset).toHaveBeenCalledWith(7);
    expect(presetRows(wrapper)).toHaveLength(0);
  });

  it('edita o nome e os filtros da jogada', async () => {
    AutonomiaProspectingAPI.updateSavedPreset.mockResolvedValue({
      data: {
        payload: savedPayload({
          name: 'Só sem site',
          filters: { has_website: 'no' },
        }),
      },
    });
    const wrapper = await mountPage();

    await buttonWithText(presetRows(wrapper)[0], `${PRESETS}.EDIT`).trigger(
      'click'
    );
    await editModal(wrapper).find('input[type="text"]').setValue('Só sem site');
    await buttonWithText(editModal(wrapper), `${PRESETS}.SAVE`).trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.updateSavedPreset).toHaveBeenCalledWith(7, {
      name: 'Só sem site',
      filters: expect.objectContaining({ has_website: 'no', has_phone: 'yes' }),
    });
    expect(editModal(wrapper).exists()).toBe(false);
    expect(presetRows(wrapper)[0].text()).toContain('Só sem site');
    expect(presetRows(wrapper)[0].text()).not.toContain(TAG('HAS_PHONE_YES'));
  });

  it('recusa do servidor na edição aparece na janela', async () => {
    AutonomiaProspectingAPI.updateSavedPreset.mockRejectedValue({
      response: { data: { error: 'Nome repetido.' } },
    });
    const wrapper = await mountPage();

    await buttonWithText(presetRows(wrapper)[0], `${PRESETS}.EDIT`).trigger(
      'click'
    );
    await buttonWithText(editModal(wrapper), `${PRESETS}.SAVE`).trigger(
      'click'
    );
    await flushPromises();

    expect(editModal(wrapper).find('[role="alert"]').text()).toBe(
      'Nome repetido.'
    );
    expect(presetRows(wrapper)[0].text()).toContain('Sem site com telefone');
  });
});
