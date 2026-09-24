<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { yesNoAnyOptions } from '../../utils/searchChoices';

const { t } = useI18n();
const { advancedFilters, activeAdvancedFiltersCount } =
  useProspectingSearchContext();

const yesNoAnyChoices = computed(() => yesNoAnyOptions(t));
</script>

<template>
  <details class="rounded-md border border-n-weak bg-n-solid-2 px-3 py-2">
    <summary
      class="flex cursor-pointer list-none items-center justify-between gap-3 text-sm font-semibold text-n-slate-12"
    >
      <span class="inline-flex items-center gap-2">
        <span class="i-lucide-sliders-horizontal size-4" />
        {{ t('PROSPECTING.SEARCH.SECTIONS.ADVANCED') }}
      </span>
      <span
        v-if="activeAdvancedFiltersCount"
        class="rounded-full bg-n-brand px-2 py-0.5 text-[11px] font-semibold text-white"
      >
        {{
          t('PROSPECTING.SEARCH.ACTIVE_FILTERS', {
            count: activeAdvancedFiltersCount,
          })
        }}
      </span>
    </summary>
    <p class="mt-2 text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.ADVANCED_FILTERS_HINT') }}
    </p>
    <div class="mt-3 grid gap-3 sm:grid-cols-2">
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.HAS_SITE') }}
        </span>
        <ChoiceSelect
          v-model="advancedFilters.has_website"
          compact
          :options="yesNoAnyChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.HAS_SITE')"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.HAS_PHONE') }}
        </span>
        <ChoiceSelect
          v-model="advancedFilters.has_phone"
          compact
          :options="yesNoAnyChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.HAS_PHONE')"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.HAS_PHOTOS') }}
        </span>
        <ChoiceSelect
          v-model="advancedFilters.has_photos"
          compact
          :options="yesNoAnyChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.HAS_PHOTOS')"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.OPEN_NOW') }}
        </span>
        <ChoiceSelect
          v-model="advancedFilters.open_now"
          compact
          :options="yesNoAnyChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.OPEN_NOW')"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.RATING_MIN') }}
        </span>
        <input
          v-model="advancedFilters.rating_min"
          type="number"
          min="0"
          max="5"
          step="0.1"
          class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.RATING_MAX') }}
        </span>
        <input
          v-model="advancedFilters.rating_max"
          type="number"
          min="0"
          max="5"
          step="0.1"
          class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.REVIEWS_MIN') }}
        </span>
        <input
          v-model="advancedFilters.reviews_min"
          type="number"
          min="0"
          class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
        />
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.SEARCH_RANK_MAX') }}
        </span>
        <input
          v-model="advancedFilters.search_rank_max"
          type="number"
          min="1"
          class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
        />
      </label>
    </div>
  </details>
</template>
