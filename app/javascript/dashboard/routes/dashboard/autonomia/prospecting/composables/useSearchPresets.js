// Frente de modo e jogadas: modo mostrado no selo do topo, jogadas do
// formulário e as regras que desmarcam a jogada (#677).
//   - escolher jogada só vale com o formulário de nova busca aberto;
//   - filtros que deixam de ser os da jogada desmarcam a jogada e ficam;
//   - "Sem jogada" sempre volta os filtros ao padrão, como no Orth;
//   - trocar o modo desmarca a jogada que não é do modo novo e tira os filtros
//     dela (jogada marcada quer dizer filtros iguais aos dela).
// Jogadas salvas da conta (#732) vêm em settings.saved_presets e valem como as
// prontas: aparecem na grade do modo delas e marcam, desmarcam e vão no pedido.
// Os filtros do formulário (formFilters, vão no pedido) e o refino da busca
// aberta (resultFilters) são estados separados (frente B). A jogada do
// formulário segue formFilters; a jogada da busca aberta segue resultFilters.
import { computed, watch } from 'vue';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { defaultAdvancedLeadFilters } from '../utils/advancedLeadFilters';
import {
  filtersMatchPreset,
  findPreset,
  presetFilters,
  presetsForScoreMode,
  savedPresetToPreset,
} from '../utils/searchPresets';
import { DEFAULT_SCORE_MODE } from './searchSlices/modeSlice';

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

  const savedPresets = computed(() =>
    (settings.value?.saved_presets || []).map(savedPresetToPreset)
  );
  const findSearchPreset = presetId => findPreset(presetId, savedPresets.value);
  const diverges = (presetId, filters) => {
    const preset = findSearchPreset(presetId);
    return Boolean(preset) && !filtersMatchPreset(filters, preset);
  };

  const formPresets = computed(() =>
    presetsForScoreMode(form.value.score_mode, savedPresets.value)
  );

  const openSearchPreset = computed(() =>
    findSearchPreset(openSearchPresetId.value)
  );

  const clearFormPreset = () => {
    form.value.preset_id = null;
    formFilters.value = defaultAdvancedLeadFilters();
  };

  // Clicar na jogada marcada, ou em "Sem jogada", volta à busca livre.
  const selectPreset = presetId => {
    if (!showNewSearch.value) return;

    const preset = findSearchPreset(presetId);
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
      const preset = findSearchPreset(form.value.preset_id);
      if (preset && preset.scoreMode !== scoreMode) clearFormPreset();
    }
  );

  // "Salvar como jogada" (#732): os filtros do formulário, no modo dele. A
  // jogada nova entra na lista da conta e fica marcada. Devolve { saved: true }
  // ou { error } com a frase da recusa do servidor (vazia sem resposta).
  const saveFormPreset = async name => {
    try {
      const { data } = await AutonomiaProspectingAPI.createSavedPreset({
        name: name.trim(),
        score_mode: form.value.score_mode,
        filters: { ...formFilters.value },
      });
      settings.value = {
        ...settings.value,
        saved_presets: [data.payload, ...(settings.value?.saved_presets || [])],
      };
      form.value.preset_id = data.payload.preset_id;
      return { saved: true };
    } catch (error) {
      return { saved: false, error: error?.response?.data?.error || '' };
    }
  };

  return {
    currentScoreMode,
    formPresets,
    openSearchPreset,
    findSearchPreset,
    saveFormPreset,
    selectPreset,
  };
};
