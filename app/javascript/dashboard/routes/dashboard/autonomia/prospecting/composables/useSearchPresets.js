// Frente de modo e jogadas: modo mostrado no selo do topo, jogadas do
// formulário e as regras que desmarcam a jogada (#677).
//   - escolher jogada só vale com o formulário de nova busca aberto;
//   - filtros que deixam de ser os da jogada desmarcam a jogada e ficam;
//   - trocar o modo desmarca a jogada que não é do modo novo.
// Os filtros avançados são um estado só para o formulário e para o refino dos
// resultados; com o formulário aberto a regra vale para a jogada do
// formulário, fora dele para a jogada da busca aberta.
import { computed, watch } from 'vue';
import { defaultAdvancedLeadFilters } from '../utils/advancedLeadFilters';
import {
  filtersMatchPreset,
  findPreset,
  presetFilters,
  presetsForScoreMode,
} from '../utils/searchPresets';
import { DEFAULT_SCORE_MODE } from './searchSlices/modeSlice';

export const useSearchPresets = state => {
  const {
    form,
    settings,
    showNewSearch,
    advancedFilters,
    openSearchScoreMode,
    openSearchPresetId,
  } = state;

  const currentScoreMode = computed(() => {
    if (showNewSearch.value) return form.value.score_mode;
    return (
      openSearchScoreMode.value ||
      settings.value?.search_score_mode ||
      DEFAULT_SCORE_MODE
    );
  });

  const formPresets = computed(() =>
    presetsForScoreMode(form.value.score_mode)
  );

  const openSearchPreset = computed(() => findPreset(openSearchPresetId.value));

  const clearFormPreset = () => {
    if (!form.value.preset_id) return;
    form.value.preset_id = null;
    advancedFilters.value = defaultAdvancedLeadFilters();
  };

  // Clicar na jogada marcada, ou em "Sem jogada", volta à busca livre.
  const selectPreset = presetId => {
    if (!showNewSearch.value) return;

    const preset = findPreset(presetId);
    if (!preset || preset.id === form.value.preset_id) {
      clearFormPreset();
      return;
    }

    form.value.preset_id = preset.id;
    advancedFilters.value = presetFilters(preset);
  };

  const diverges = presetId => {
    const preset = findPreset(presetId);
    return (
      Boolean(preset) && !filtersMatchPreset(advancedFilters.value, preset)
    );
  };

  watch(
    advancedFilters,
    () => {
      if (showNewSearch.value) {
        if (diverges(form.value.preset_id)) form.value.preset_id = null;
        return;
      }
      if (diverges(openSearchPresetId.value)) openSearchPresetId.value = null;
    },
    { deep: true }
  );

  watch(
    () => form.value.score_mode,
    scoreMode => {
      const preset = findPreset(form.value.preset_id);
      if (preset && preset.scoreMode !== scoreMode) form.value.preset_id = null;
    }
  );

  return {
    currentScoreMode,
    formPresets,
    openSearchPreset,
    selectPreset,
  };
};
