<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  form,
  settings,
  isSuggestingLocations,
  locationSuggestions,
  confirmedLocation,
  selectedLocationLabel,
  handleLocationInput,
  confirmLocationSuggestion,
} = useProspectingSearchContext();

const autocompleteHint = computed(() => {
  if (isSuggestingLocations.value) {
    return t('PROSPECTING.SEARCH.SUGGESTING_LOCATIONS');
  }

  if (confirmedLocation.value) {
    return t('PROSPECTING.SEARCH.LOCATION_CONFIRMED');
  }

  return settings.value?.platform_google_places_configured
    ? t('PROSPECTING.SEARCH.AUTOCOMPLETE_READY_HINT')
    : t('PROSPECTING.SEARCH.AUTOCOMPLETE_DISABLED_HINT');
});
const combinedLocationSuggestions = computed(() => {
  const seen = new Set();
  return locationSuggestions.value.filter(item => {
    const key = item.place_id || item.text;
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
});
</script>

<template>
  <label class="grid gap-1">
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('PROSPECTING.SEARCH.FIELDS.QUERY') }}
    </span>
    <input
      v-model="form.query"
      class="h-10 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
      :placeholder="t('PROSPECTING.SEARCH.QUERY_PLACEHOLDER')"
    />
  </label>

  <div class="grid gap-2">
    <label class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.LOCATION') }}
      </span>
      <input
        v-model="form.location"
        class="h-10 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
        :placeholder="t('PROSPECTING.SEARCH.LOCATION_PLACEHOLDER')"
        autocomplete="off"
        @input="handleLocationInput"
      />
    </label>
    <div class="flex items-center justify-between gap-3">
      <span class="text-xs text-n-slate-10">
        {{ autocompleteHint }}
      </span>
      <span
        v-if="confirmedLocation"
        class="inline-flex items-center gap-1 text-xs font-medium text-n-teal-11"
      >
        <span class="i-lucide-check size-3.5" />
        {{ selectedLocationLabel }}
      </span>
    </div>
    <div
      v-if="combinedLocationSuggestions.length && !confirmedLocation"
      class="overflow-hidden rounded-md border border-n-weak bg-n-solid-1"
    >
      <button
        v-for="suggestion in combinedLocationSuggestions"
        :key="suggestion.place_id || suggestion.text"
        type="button"
        class="flex w-full items-center justify-between gap-3 border-b border-n-weak px-3 py-2 text-left text-sm last:border-b-0 hover:bg-n-solid-2"
        @click="confirmLocationSuggestion(suggestion)"
      >
        <span class="min-w-0 truncate text-n-slate-12">
          {{ suggestion.text }}
        </span>
        <span class="i-lucide-map-pin size-4 shrink-0 text-n-slate-10" />
      </button>
    </div>
  </div>
</template>
