<script setup>
// Editar uma jogada salva (#732, MODO-26): nome e filtros, na mesma gaveta de
// filtros da busca. O modo não muda: a jogada continua na grade em que foi
// salva. A recusa do servidor aparece aqui e a janela fica aberta. Mora dentro
// do formulário das configurações, então não tem <form> próprio.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import LeadFiltersPanel from './search/filters/LeadFiltersPanel.vue';

const props = defineProps({
  preset: { type: Object, required: true },
});

const emit = defineEmits(['saved', 'close']);

// A janela cobre a tela inteira, inclusive o canto do lançador do Guia (#646).
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const titleId = useId();

const NAME_MAX_LENGTH = 60;
const name = ref(props.preset.name);
// Fixo durante a edição: a gaveta refaz o rascunho quando a prop muda.
const initialFilters = props.preset.filters || {};
const isSaving = ref(false);
const error = ref('');

const close = () => {
  if (!isSaving.value) emit('close');
};

const save = async filters => {
  if (isSaving.value) return;

  isSaving.value = true;
  error.value = '';
  try {
    const { data } = await AutonomiaProspectingAPI.updateSavedPreset(
      props.preset.id,
      { name: name.value.trim(), filters }
    );
    isSaving.value = false;
    emit('saved', data.payload);
  } catch (requestError) {
    isSaving.value = false;
    error.value =
      requestError?.response?.data?.error ||
      t('PROSPECTING.SETTINGS.SAVED_PRESETS.SAVE_ERROR');
  }
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
      data-test="saved-preset-edit-modal"
      class="grid max-h-[90vh] w-full max-w-xl gap-4 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="flex items-start justify-between gap-3">
        <h2 :id="titleId" class="text-base font-semibold text-n-slate-12">
          {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.EDIT_TITLE') }}
        </h2>
        <button
          type="button"
          class="flex size-11 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2"
          :aria-label="t('PROSPECTING.SETTINGS.SAVED_PRESETS.CLOSE')"
          @click="close"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </header>

      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SETTINGS.SAVED_PRESETS.NAME') }}
        </span>
        <input
          v-model="name"
          type="text"
          :maxlength="NAME_MAX_LENGTH"
          autocomplete="off"
          class="h-11 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
          @keydown.enter.prevent
        />
      </label>

      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>

      <LeadFiltersPanel
        :filters="initialFilters"
        :can-clear="false"
        :apply-label="t('PROSPECTING.SETTINGS.SAVED_PRESETS.SAVE')"
        @apply="save"
      />
    </section>
  </div>
</template>
