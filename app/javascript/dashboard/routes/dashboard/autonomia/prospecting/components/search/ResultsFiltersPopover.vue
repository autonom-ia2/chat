<script setup>
// Ordem e refino da busca aberta. A ordem vale na hora; os filtros usam a
// gaveta com rascunho e só refinam os leads em "Aplicar". Este refino não
// mexe nos filtros do formulário de nova busca.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import FiltersBaseLine from './filters/FiltersBaseLine.vue';
import LeadFiltersPanel from './filters/LeadFiltersPanel.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  sortKey,
  resultFilters,
  showFilters,
  openSearchPreset,
  currentScoreMode,
} = useProspectingSearchContext();

const sortChoices = computed(() => [
  { value: 'priority_desc', label: t('PROSPECTING.SEARCH.SORT.PRIORITY_DESC') },
  { value: 'score_desc', label: t('PROSPECTING.SEARCH.SORT.SCORE_DESC') },
  { value: 'created_desc', label: t('PROSPECTING.SEARCH.SORT.CREATED_DESC') },
  { value: 'created_asc', label: t('PROSPECTING.SEARCH.SORT.CREATED_ASC') },
  { value: 'rating_desc', label: t('PROSPECTING.SEARCH.SORT.RATING_DESC') },
  { value: 'reviews_desc', label: t('PROSPECTING.SEARCH.SORT.REVIEWS_DESC') },
  { value: 'name_asc', label: t('PROSPECTING.SEARCH.SORT.NAME_ASC') },
]);

const applyFilters = next => {
  resultFilters.value = next;
  showFilters.value = false;
};
</script>

<template>
  <div
    class="absolute right-0 top-11 z-30 grid max-h-[80vh] w-[24rem] max-w-[calc(100vw-2rem)] gap-3 overflow-y-auto rounded-md border border-n-weak bg-n-solid-1 p-3 shadow-lg"
  >
    <label class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.SORT') }}
      </span>
      <ChoiceSelect
        v-model="sortKey"
        compact
        :options="sortChoices"
        :aria-label="t('PROSPECTING.SEARCH.FIELDS.SORT')"
      />
    </label>
    <FiltersBaseLine
      :preset="openSearchPreset"
      :score-mode="currentScoreMode"
    />
    <LeadFiltersPanel :filters="resultFilters" @apply="applyFilters" />
  </div>
</template>
