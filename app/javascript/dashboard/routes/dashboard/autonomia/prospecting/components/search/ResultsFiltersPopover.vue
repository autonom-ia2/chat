<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { yesNoAnyOptions } from '../../utils/searchChoices';

const { t } = useI18n();
const { sortKey, advancedFilters } = useProspectingSearchContext();

const yesNoAnyChoices = computed(() => yesNoAnyOptions(t));
const sortChoices = computed(() => [
  { value: 'priority_desc', label: t('PROSPECTING.SEARCH.SORT.PRIORITY_DESC') },
  { value: 'score_desc', label: t('PROSPECTING.SEARCH.SORT.SCORE_DESC') },
  { value: 'created_desc', label: t('PROSPECTING.SEARCH.SORT.CREATED_DESC') },
  { value: 'created_asc', label: t('PROSPECTING.SEARCH.SORT.CREATED_ASC') },
  { value: 'rating_desc', label: t('PROSPECTING.SEARCH.SORT.RATING_DESC') },
  { value: 'reviews_desc', label: t('PROSPECTING.SEARCH.SORT.REVIEWS_DESC') },
  { value: 'name_asc', label: t('PROSPECTING.SEARCH.SORT.NAME_ASC') },
]);
</script>

<template>
  <div
    class="absolute right-0 top-11 z-30 grid w-[22rem] gap-3 rounded-md border border-n-weak bg-n-solid-1 p-3 shadow-lg"
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
    <div class="grid gap-2 sm:grid-cols-2">
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
    </div>
    <div class="grid gap-2 sm:grid-cols-2">
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
    </div>
    <div class="grid gap-2 sm:grid-cols-2">
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
          class="h-9 rounded-md border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
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
          class="h-9 rounded-md border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
        />
      </label>
    </div>
    <div class="grid gap-2 sm:grid-cols-2">
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.REVIEWS_MIN') }}
        </span>
        <input
          v-model="advancedFilters.reviews_min"
          type="number"
          min="0"
          class="h-9 rounded-md border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
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
          class="h-9 rounded-md border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
        />
      </label>
    </div>
  </div>
</template>
