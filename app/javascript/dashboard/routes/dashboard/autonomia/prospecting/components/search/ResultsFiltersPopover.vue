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
import {
  SORT_FIELDS,
  defaultSortDirection,
  parseSortKey,
  sortKeyFor,
} from '../../utils/sortLeads';

const { t } = useI18n();
const {
  sortKey,
  openSearchCenter,
  resultFilters,
  showFilters,
  openSearchPreset,
  currentScoreMode,
} = useProspectingSearchContext();

// Campo e direção (#678). Distância só com o centro da busca aberta.
const sortChoices = computed(() => {
  const labels = {
    priority: t('PROSPECTING.SEARCH.SORT.FIELDS.PRIORITY'),
    score: t('PROSPECTING.SEARCH.SORT.FIELDS.SCORE'),
    rating: t('PROSPECTING.SEARCH.SORT.FIELDS.RATING'),
    reviews: t('PROSPECTING.SEARCH.SORT.FIELDS.REVIEWS'),
    distance: t('PROSPECTING.SEARCH.SORT.FIELDS.DISTANCE'),
    google_rank: t('PROSPECTING.SEARCH.SORT.FIELDS.GOOGLE_RANK'),
    created: t('PROSPECTING.SEARCH.SORT.FIELDS.CREATED'),
    name: t('PROSPECTING.SEARCH.SORT.FIELDS.NAME'),
  };
  return SORT_FIELDS.filter(
    field => field !== 'distance' || openSearchCenter.value
  ).map(field => ({ value: field, label: labels[field] }));
});
const currentSort = computed(() => parseSortKey(sortKey.value));
// Trocar o campo volta para a direção que põe o melhor primeiro.
const sortField = computed({
  get: () => currentSort.value.field,
  set: field => {
    sortKey.value = sortKeyFor(field, defaultSortDirection(field));
  },
});
const isAscending = computed(() => currentSort.value.direction === 'asc');
const directionLabel = computed(() =>
  isAscending.value
    ? t('PROSPECTING.SEARCH.SORT.DIRECTION.ASC')
    : t('PROSPECTING.SEARCH.SORT.DIRECTION.DESC')
);
const invertSortDirection = () => {
  sortKey.value = sortKeyFor(
    currentSort.value.field,
    isAscending.value ? 'desc' : 'asc'
  );
};

const applyFilters = next => {
  resultFilters.value = next;
  showFilters.value = false;
};
</script>

<template>
  <div
    class="absolute right-0 top-11 z-30 grid max-h-[80vh] w-[24rem] max-w-[calc(100vw-2rem)] gap-3 overflow-y-auto rounded-md border border-n-weak bg-n-solid-1 p-3 shadow-lg"
  >
    <div class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.SORT') }}
      </span>
      <div class="flex items-center gap-2">
        <ChoiceSelect
          v-model="sortField"
          class="min-w-0 flex-1"
          compact
          :options="sortChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.SORT')"
        />
        <button
          type="button"
          data-test="sort-direction"
          class="inline-flex size-11 shrink-0 items-center justify-center gap-1 rounded-md border border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-solid-2"
          :aria-label="
            t('PROSPECTING.SEARCH.SORT.INVERT', { direction: directionLabel })
          "
          :title="directionLabel"
          @click="invertSortDirection"
        >
          <span
            class="size-4"
            :class="
              isAscending
                ? 'i-lucide-arrow-up-narrow-wide'
                : 'i-lucide-arrow-down-wide-narrow'
            "
          />
        </button>
      </div>
    </div>
    <FiltersBaseLine
      :preset="openSearchPreset"
      :score-mode="currentScoreMode"
    />
    <LeadFiltersPanel :filters="resultFilters" @apply="applyFilters" />
  </div>
</template>
