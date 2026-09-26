<script setup>
// Janela "Salvar como jogada" (#732; MODO-25, FILTRO-27), como a do Orth: nome
// da jogada e o resumo dos filtros em etiquetas. Salva os filtros do formulário
// no modo dele; a recusa do servidor aparece aqui e a janela fica aberta. Mora
// dentro do formulário da busca: sem <form> próprio, Enter no nome salva a
// jogada em vez de disparar a busca.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { filterSummaryTags } from '../../utils/searchPresets';

const emit = defineEmits(['close']);

// A janela cobre a tela inteira, inclusive o canto do lançador do Guia (#646).
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const titleId = useId();
const { formFilters, saveFormPreset } = useProspectingSearchContext();

const NAME_MAX_LENGTH = 60;
const name = ref('');
const isSaving = ref(false);
const error = ref('');

const tags = computed(() => filterSummaryTags(formFilters.value, t));
const canSave = computed(() => name.value.trim() !== '' && !isSaving.value);

const close = () => {
  if (!isSaving.value) emit('close');
};

const save = async () => {
  if (!canSave.value) return;

  isSaving.value = true;
  error.value = '';
  const result = await saveFormPreset(name.value);
  isSaving.value = false;
  if (result.saved) {
    emit('close');
    return;
  }
  error.value = result.error || t('PROSPECTING.SEARCH.SAVED_PRESETS.ERROR');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/30 px-4"
    @click.self="close"
    @keydown.esc="close"
  >
    <section
      role="dialog"
      aria-modal="true"
      :aria-labelledby="titleId"
      data-test="save-preset-modal"
      class="grid w-full max-w-md gap-4 rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="grid gap-1">
        <h2 :id="titleId" class="text-base font-semibold text-n-slate-12">
          {{ t('PROSPECTING.SEARCH.SAVED_PRESETS.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.SAVED_PRESETS.DESCRIPTION') }}
        </p>
      </header>

      <div class="grid gap-3">
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('PROSPECTING.SEARCH.SAVED_PRESETS.NAME') }}
          </span>
          <input
            v-model="name"
            type="text"
            :maxlength="NAME_MAX_LENGTH"
            :placeholder="
              t('PROSPECTING.SEARCH.SAVED_PRESETS.NAME_PLACEHOLDER')
            "
            autocomplete="off"
            class="h-11 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
            @keydown.enter.prevent="save"
          />
        </label>
        <ul v-if="tags.length" class="flex flex-wrap gap-1.5">
          <li
            v-for="tag in tags"
            :key="tag"
            class="rounded-full bg-n-solid-3 px-2 py-0.5 text-xs text-n-slate-11"
          >
            {{ tag }}
          </li>
        </ul>
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <footer class="flex justify-end gap-2">
          <button
            type="button"
            class="min-h-11 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="isSaving"
            @click="close"
          >
            {{ t('PROSPECTING.SEARCH.SAVED_PRESETS.CANCEL') }}
          </button>
          <button
            type="button"
            class="min-h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="!canSave"
            @click="save"
          >
            {{ t('PROSPECTING.SEARCH.SAVED_PRESETS.SAVE') }}
          </button>
        </footer>
      </div>
    </section>
  </div>
</template>
