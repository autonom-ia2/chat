// Frente de modo e jogadas: modo mostrado no selo do topo, jogadas do
// formulário e as regras que desmarcam a jogada (#677).
//   - escolher jogada só vale com o formulário de nova busca aberto;
//   - filtros que deixam de ser os da jogada desmarcam a jogada e ficam;
//   - trocar o modo desmarca a jogada que não é do modo novo.
// Os filtros do formulário (formFilters, vão no pedido) e o refino da busca
// aberta (resultFilters) são estados separados (frente B). A jogada do
// formulário segue formFilters; a jogada da busca aberta segue resultFilters.
import { computed, watch } from 'vue';
import { defaultAdvancedLeadFilters } from '../utils/advancedLeadFilters';
import {
  filtersMatchPreset,
  findPreset,
  presetFilters,
  presetsForScoreMode,
} from '../utils/searchPresets';
import { DEFAULT_SCORE_MODE } from './searchSlices/modeSlice';

const diverges = (presetId, filters) => {
  const preset = findPreset(presetId);
  return Boolean(preset) && !filtersMatchPreset(filters, preset);
};

export const useSearchPresets = state => {
  const {
    form,
    settings,
    showNewSearch,
    formFilters,
    resultFilters,
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
    formFilters.value = defaultAdvancedLeadFilters();
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
    formFilters.value = presetFilters(preset);
  };

  watch(
    formFilters,
    filters => {
      if (diverges(form.value.preset_id, filters)) form.value.preset_id = null;
    },
    { deep: true }
  );

  watch(
    resultFilters,
    filters => {
      if (diverges(openSearchPresetId.value, filters)) {
        openSearchPresetId.value = null;
      }
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
