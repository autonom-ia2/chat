// Frente de modo e jogadas: como a busca pontua os leads.
const DEFAULT_SCORE_MODE = 'gbp';

export const modeSlice = {
  formDefaults: settings => ({
    score_mode: settings.value?.search_score_mode || DEFAULT_SCORE_MODE,
  }),
  toPayload: ({ form, settings }) => ({
    metadata: {
      score_mode:
        form.value.score_mode ||
        settings.value?.search_score_mode ||
        DEFAULT_SCORE_MODE,
      scoring_profile_id: settings.value?.scoring_profile_id,
    },
  }),
};
