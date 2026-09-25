// Frente de modo e jogadas: como a busca pontua os leads e qual jogada a
// montou. O formulário guarda o modo e a jogada da nova busca; a busca aberta
// guarda os dela, restaurados ao reabrir (o selo do topo lê daqui).
import { ref } from 'vue';

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
      preset_id: search.preset_id || null,
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
