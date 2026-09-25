// Frente de modo e jogadas: como a busca pontua os leads e qual jogada a
// montou. O formulário guarda o modo e a jogada da nova busca; a busca aberta
// guarda os dela, restaurados ao reabrir (o selo do topo lê daqui).
import { ref } from 'vue';
import { findPreset, savedPresetToPreset } from '../../utils/searchPresets';

// A jogada da busca só volta ao formulário se ainda existe: a jogada salva
// excluída nas Configurações iria no pedido e o servidor recusaria (#732). Os
// filtros da busca voltam do mesmo jeito (filtersSlice).
const existingPresetId = (presetId, settings) => {
  if (!presetId) return null;
  const saved = (settings.value?.saved_presets || []).map(savedPresetToPreset);
  return findPreset(presetId, saved) ? presetId : null;
};

export const DEFAULT_SCORE_MODE = 'gbp';

export const modeSlice = {
  formDefaults: settings => ({
    score_mode: settings.value?.search_score_mode || DEFAULT_SCORE_MODE,
    preset_id: null,
  }),
  createState: () => ({
    openSearchScoreMode: ref(null),
    openSearchPresetId: ref(null),
  }),
  restore: ({ openSearchScoreMode, openSearchPresetId }, search) => {
    openSearchScoreMode.value = search?.score_mode || null;
    openSearchPresetId.value = search?.preset_id || null;
  },
  restoreForm: ({ form, settings }, search) => {
    form.value = {
      ...form.value,
      score_mode:
        search.score_mode ||
        settings.value?.search_score_mode ||
        DEFAULT_SCORE_MODE,
      preset_id: existingPresetId(search.preset_id, settings),
    };
  },
  toPayload: ({ form, settings }) => ({
    metadata: {
      score_mode:
        form.value.score_mode ||
        settings.value?.search_score_mode ||
        DEFAULT_SCORE_MODE,
      preset_id: form.value.preset_id || null,
      scoring_profile_id: settings.value?.scoring_profile_id,
    },
  }),
};
