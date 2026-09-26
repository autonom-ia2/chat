<script setup>
// Jogadas salvas da conta nas Configurações da Prospecção (#732, MODO-26):
// nome, modo e resumo dos filtros, com editar e excluir. Excluir pede uma
// segunda confirmação na própria linha. A lista chega e volta pelo v-model,
// que é o saved_presets do payload das configurações.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import SavedPresetEditModal from './SavedPresetEditModal.vue';
import { filterSummaryTags } from '../utils/searchPresets';

const presets = defineModel({ type: Array, required: true });

const { t } = useI18n();
const confirmingDeleteId = ref(null);
const deletingId = ref(null);
const editingPreset = ref(null);

const modeLabel = scoreMode =>
  scoreMode === 'gbp'
    ? t('PROSPECTING.SEARCH.SCORE_MODES.GBP')
    : t('PROSPECTING.SEARCH.SCORE_MODES.GENERAL');

const deletePreset = async preset => {
  deletingId.value = preset.id;
  try {
    await AutonomiaProspectingAPI.deleteSavedPreset(preset.id);
    presets.value = presets.value.filter(item => item.id !== preset.id);
    useAlert(t('PROSPECTING.SETTINGS.SAVED_PRESETS.DELETED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('PROSPECTING.SETTINGS.SAVED_PRESETS.DELETE_ERROR')
    );
  } finally {
    deletingId.value = null;
    confirmingDeleteId.value = null;
  }
};

const replacePreset = updated => {
  presets.value = presets.value.map(item =>
    item.id === updated.id ? updated : item
  );
  editingPreset.value = null;
};
</script>

<template>
  <section class="grid gap-3">
    <div class="grid gap-1">
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.TITLE') }}
      </h2>
      <p class="max-w-2xl text-sm text-n-slate-10">
        {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.HINT') }}
      </p>
    </div>

    <p
      v-if="!presets.length"
      class="rounded-md border border-dashed border-n-weak px-4 py-6 text-sm text-n-slate-11"
    >
      {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.EMPTY') }}
    </p>

    <ul v-else class="grid gap-2">
      <li
        v-for="preset in presets"
        :key="preset.id"
        data-test="saved-preset-row"
        class="flex flex-col gap-3 rounded-md border border-n-weak bg-n-solid-2 p-3 md:flex-row md:items-center md:justify-between"
      >
        <div class="grid min-w-0 gap-1.5">
          <div class="flex flex-wrap items-center gap-2">
            <span class="i-lucide-bookmark size-4 text-n-slate-11" />
            <strong class="truncate text-sm font-semibold text-n-slate-12">
              {{ preset.name }}
            </strong>
            <span
              class="rounded-full border border-n-weak px-2 py-0.5 text-[11px] text-n-slate-11"
            >
              {{ modeLabel(preset.score_mode) }}
            </span>
          </div>
          <ul class="flex flex-wrap gap-1.5">
            <li
              v-for="tag in filterSummaryTags(preset.filters || {}, t)"
              :key="tag"
              class="rounded-full bg-n-solid-3 px-2 py-0.5 text-xs text-n-slate-11"
            >
              {{ tag }}
            </li>
          </ul>
        </div>

        <div class="flex shrink-0 items-center gap-2">
          <template v-if="confirmingDeleteId === preset.id">
            <button
              type="button"
              class="min-h-11 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-3"
              :disabled="deletingId === preset.id"
              @click="confirmingDeleteId = null"
            >
              {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.CANCEL') }}
            </button>
            <button
              type="button"
              class="min-h-11 rounded-md bg-n-ruby-9 px-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="deletingId === preset.id"
              @click="deletePreset(preset)"
            >
              {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.CONFIRM_DELETE') }}
            </button>
          </template>
          <template v-else>
            <button
              type="button"
              class="min-h-11 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-3"
              @click="editingPreset = preset"
            >
              {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.EDIT') }}
            </button>
            <button
              type="button"
              class="min-h-11 rounded-md px-3 text-sm font-medium text-n-ruby-11 hover:bg-n-ruby-3"
              @click="confirmingDeleteId = preset.id"
            >
              {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.DELETE') }}
            </button>
          </template>
        </div>
      </li>
    </ul>

    <SavedPresetEditModal
      v-if="editingPreset"
      :preset="editingPreset"
      @saved="replacePreset"
      @close="editingPreset = null"
    />
  </section>
</template>
