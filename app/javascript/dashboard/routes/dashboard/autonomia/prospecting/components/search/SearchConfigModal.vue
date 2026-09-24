<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  crmPipelines,
  searchConfigStages,
  searchConfigForm,
  selectedSearchConfig,
  editingSearchConfigId,
  fetchSearchConfigStages,
  saveSearchConfig,
} = useProspectingSearchContext();

const searchConfigPipelineChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SEARCH.CRM_DISABLED_SHORT') },
  ...crmPipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  })),
]);
const searchConfigStageChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SEARCH.CRM_STAGE_EMPTY') },
  ...searchConfigStages.value.map(stage => ({
    value: stage.id,
    label: stage.name,
  })),
]);
</script>

<template>
  <div
    class="fixed inset-0 z-40 flex items-center justify-center bg-n-slate-12/30 px-4"
    @click.self="editingSearchConfigId = null"
  >
    <section
      class="grid w-full max-w-md gap-4 rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('PROSPECTING.SEARCH.CONFIGURE_SEARCH') }}
          </h2>
          <p class="mt-1 truncate text-sm text-n-slate-10">
            {{ selectedSearchConfig.query }}
          </p>
        </div>
        <button
          type="button"
          class="flex size-8 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2"
          :title="t('PROSPECTING.SEARCH.CLOSE_DETAILS')"
          @click="editingSearchConfigId = null"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.CRM_PIPELINE') }}
        </span>
        <ChoiceSelect
          v-model="searchConfigForm.crm_pipeline_id"
          :options="searchConfigPipelineChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.CRM_PIPELINE')"
          @change="fetchSearchConfigStages(searchConfigForm.crm_pipeline_id)"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.CRM_STAGE') }}
        </span>
        <ChoiceSelect
          v-model="searchConfigForm.crm_stage_id"
          :options="searchConfigStageChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.CRM_STAGE')"
        />
      </label>
      <footer class="flex justify-end gap-2">
        <button
          type="button"
          class="h-9 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2"
          @click="editingSearchConfigId = null"
        >
          {{ t('PROSPECTING.LISTS.CANCEL') }}
        </button>
        <button
          type="button"
          class="h-9 rounded-md bg-n-brand px-3 text-sm font-medium text-white"
          @click="saveSearchConfig(selectedSearchConfig)"
        >
          {{ t('PROSPECTING.SEARCH.SAVE_CONFIG') }}
        </button>
      </footer>
    </section>
  </div>
</template>
