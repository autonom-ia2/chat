<script setup>
import { useI18n } from 'vue-i18n';
import ProspectingGoogleMap from '../ProspectingGoogleMap.vue';
import SearchWhereFields from './SearchWhereFields.vue';
import SearchAreaFields from './SearchAreaFields.vue';
import SearchModeFields from './SearchModeFields.vue';
import SearchQuantityFields from './SearchQuantityFields.vue';
import SearchAdvancedFilters from './SearchAdvancedFilters.vue';
import SearchSummary from './SearchSummary.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  form,
  canSearch,
  isSearching,
  confirmedLocation,
  googleMapsApiKey,
  previewMapCenter,
  previewMapRadius,
  previewAreaBounds,
  submitSearch,
  handlePreviewViewportChange,
} = useProspectingSearchContext();
</script>

<template>
  <form
    class="min-h-0 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1"
    @submit.prevent="submitSearch"
  >
    <section class="border-b border-n-weak px-5 py-4">
      <div
        class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"
      >
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('PROSPECTING.SEARCH.SECTIONS.WHERE') }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-10">
            {{ t('PROSPECTING.SEARCH.LOCATION_HINT') }}
          </p>
        </div>
        <button
          type="submit"
          class="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-n-brand px-4 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!canSearch"
        >
          <span class="i-lucide-search size-4" />
          {{
            isSearching
              ? t('PROSPECTING.SEARCH.SEARCHING')
              : t('PROSPECTING.SEARCH.ACTION')
          }}
        </button>
      </div>
    </section>

    <section class="grid gap-5 p-5 xl:grid-cols-[minmax(0,1fr)_20rem]">
      <div class="grid content-start gap-5">
        <div class="grid gap-4">
          <SearchWhereFields />
          <SearchAreaFields />
          <SearchModeFields />
          <SearchQuantityFields />
          <SearchAdvancedFilters />
        </div>

        <ProspectingGoogleMap
          v-if="confirmedLocation && previewMapCenter"
          :api-key="googleMapsApiKey"
          :center="previewMapCenter"
          :radius="previewMapRadius"
          :bounds="previewAreaBounds"
          :fit-on-render="form.area_type === 'radius'"
          height-class="h-80"
          @viewport-change="handlePreviewViewportChange"
        />
      </div>

      <SearchSummary />
    </section>
  </form>
</template>
