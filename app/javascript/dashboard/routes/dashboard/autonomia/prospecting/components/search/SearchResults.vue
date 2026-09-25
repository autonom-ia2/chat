<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ProspectingGoogleMap from '../ProspectingGoogleMap.vue';
import ResultsFiltersPopover from './ResultsFiltersPopover.vue';
import BulkActionsBar from './BulkActionsBar.vue';
import LeadCard from './LeadCard.vue';
import ResearchProgressBar from './ResearchProgressBar.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import * as formatters from '../../utils/searchFormatters';

const { t } = useI18n();
const {
  isLoading,
  isSearching,
  hasResults,
  sortedLeads,
  selectedSearch,
  selectedLeadDetailId,
  showFilters,
  activeFiltersCount,
  googleMapsApiKey,
  exportLeads,
  isExporting,
  researchProgress,
} = useProspectingSearchContext();

const formatSearchArea = search => formatters.formatSearchArea(search, t);

// Exportação (#682): o botão de download abre a escolha entre CSV e Excel.
const showExportMenu = ref(false);
const exportMenuItems = computed(() => [
  {
    label: t('PROSPECTING.SEARCH.EXPORT_CSV'),
    value: 'csv',
    action: 'export',
    icon: 'i-lucide-file-text',
  },
  {
    label: t('PROSPECTING.SEARCH.EXPORT_XLSX'),
    value: 'xlsx',
    action: 'export',
    icon: 'i-lucide-file-spreadsheet',
  },
]);
const chooseExportFormat = ({ value }) => {
  showExportMenu.value = false;
  exportLeads(value);
};
const mapLeads = computed(() =>
  sortedLeads.value.filter(lead => lead.latitude && lead.longitude)
);
const resultsMapCenter = computed(() => {
  if (selectedSearch.value?.area_config?.center) {
    return {
      lat: Number(selectedSearch.value.area_config.center.lat),
      lng: Number(selectedSearch.value.area_config.center.lng),
    };
  }

  if (
    selectedSearch.value?.location_latitude &&
    selectedSearch.value?.location_longitude
  ) {
    return {
      lat: Number(selectedSearch.value.location_latitude),
      lng: Number(selectedSearch.value.location_longitude),
    };
  }

  return null;
});
const selectedSearchAreaBounds = computed(() =>
  selectedSearch.value?.area_type === 'viewport'
    ? selectedSearch.value?.area_config?.bounds
    : null
);
const selectedSearchMapRadius = computed(() =>
  selectedSearch.value?.area_type === 'radius'
    ? selectedSearch.value?.radius || 1000
    : 0
);
</script>

<template>
  <section
    data-tour="search-results"
    class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
  >
    <div
      class="flex flex-col gap-3 border-b border-n-weak px-4 py-3 lg:flex-row lg:items-end lg:justify-between"
    >
      <div class="min-w-0">
        <h2 class="truncate text-sm font-semibold text-n-slate-12">
          {{
            selectedSearch
              ? t('PROSPECTING.SEARCH.RESULTS_FOR', {
                  query: selectedSearch.query,
                })
              : t('PROSPECTING.SEARCH.RESULTS_TITLE')
          }}
        </h2>
        <p class="mt-1 truncate text-xs text-n-slate-10">
          {{
            selectedSearch?.location || t('PROSPECTING.SEARCH.RESULTS_EMPTY')
          }}
        </p>
      </div>
      <div class="relative flex items-center gap-2">
        <button
          type="button"
          class="relative flex size-9 items-center justify-center rounded-md border border-n-weak text-n-slate-12 hover:bg-n-solid-2"
          :title="t('PROSPECTING.SEARCH.FILTER_BUTTON')"
          @click="showFilters = !showFilters"
        >
          <span class="i-lucide-sliders-horizontal size-4" />
          <span
            v-if="activeFiltersCount"
            class="absolute -right-1 -top-1 flex size-4 items-center justify-center rounded-full bg-n-brand text-[10px] font-semibold text-white"
          >
            {{ activeFiltersCount }}
          </span>
        </button>
        <button
          type="button"
          class="flex size-9 items-center justify-center rounded-md border border-n-weak text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!sortedLeads.length || isExporting"
          :title="t('PROSPECTING.SEARCH.CSV_EXPORT')"
          :aria-label="t('PROSPECTING.SEARCH.CSV_EXPORT')"
          aria-haspopup="menu"
          :aria-expanded="showExportMenu"
          @click="showExportMenu = !showExportMenu"
        >
          <span
            class="size-4"
            :class="
              isExporting
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-download'
            "
          />
        </button>
        <DropdownMenu
          v-if="showExportMenu"
          :menu-items="exportMenuItems"
          class="end-0 top-full z-20 mt-1 w-44"
          @action="chooseExportFormat"
        />
        <ResultsFiltersPopover v-if="showFilters" />
      </div>
    </div>

    <div class="min-h-0 flex-1 overflow-x-hidden overflow-y-auto">
      <section class="border-b border-n-weak p-4">
        <div class="mb-3 flex items-start justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('PROSPECTING.SEARCH.MAP_TITLE') }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ t('PROSPECTING.SEARCH.MAP_HINT') }}
            </p>
          </div>
          <span class="text-xs text-n-slate-10">
            {{ formatSearchArea(selectedSearch) }}
          </span>
        </div>
        <ProspectingGoogleMap
          v-if="mapLeads.length || resultsMapCenter"
          :api-key="googleMapsApiKey"
          :center="resultsMapCenter"
          :radius="selectedSearchMapRadius"
          :bounds="selectedSearchAreaBounds"
          :leads="mapLeads"
          height-class="h-80"
          @select-lead="selectedLeadDetailId = $event.id"
        />
        <div
          v-else
          class="flex h-80 items-center justify-center rounded-md border border-n-weak bg-n-solid-2 px-4 text-center text-xs text-n-slate-10"
        >
          {{ t('PROSPECTING.SEARCH.MAP_NO_COORDINATES') }}
        </div>
      </section>
      <div>
        <div
          v-if="isSearching || isLoading"
          class="px-4 py-8 text-sm text-n-slate-11"
        >
          {{ t('PROSPECTING.STATES.LOADING') }}
        </div>
        <div v-else-if="!hasResults" class="px-4 py-8 text-sm text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.RESULTS_EMPTY') }}
        </div>
        <div
          v-else-if="!sortedLeads.length"
          class="px-4 py-8 text-sm text-n-slate-11"
        >
          {{ t('PROSPECTING.QUALITY.NO_STATUS_RESULTS') }}
        </div>
        <div v-else class="grid min-w-0 gap-3 p-4">
          <ResearchProgressBar :progress="researchProgress" />
          <BulkActionsBar />
          <LeadCard v-for="lead in sortedLeads" :key="lead.id" :lead="lead" />
        </div>
      </div>
    </div>
  </section>
</template>
